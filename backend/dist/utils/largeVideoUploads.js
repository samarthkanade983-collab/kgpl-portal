import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { safeUploadName } from './upload.js';
export class UploadSessionError extends Error {
    statusCode;
    constructor(message, statusCode = 400) {
        super(message);
        this.statusCode = statusCode;
    }
}
// Direct uploads previously travelled as base64 inside a 100 MB JSON body.
// Chunked uploads stream to disk instead, so the cap is only bounded by what
// the operator is willing to store locally.
export const MAX_VIDEO_UPLOAD_BYTES = Number(process.env.MAX_VIDEO_UPLOAD_BYTES || 50 * 1024 * 1024 * 1024);
export const MAX_CHUNK_BYTES = 40 * 1024 * 1024;
export const VIDEO_UPLOAD_EXTENSIONS = new Set([
    '.mp4', '.m4v', '.mov', '.webm', '.ogv', '.ogg',
]);
const UPLOAD_ROOT = path.resolve('uploads');
const TEMP_DIR = path.join(UPLOAD_ROOT, 'tmp');
const VIDEO_DIR = path.join(UPLOAD_ROOT, 'videos');
const SESSION_TTL_MS = 24 * 60 * 60 * 1000;
const DISK_HEADROOM_BYTES = 1024 * 1024 * 1024;
const sessions = new Map();
function ensureDirs() {
    fs.mkdirSync(TEMP_DIR, { recursive: true });
    fs.mkdirSync(VIDEO_DIR, { recursive: true });
}
function sessionIdPattern(id) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id);
}
function partPath(id) {
    return path.join(TEMP_DIR, `${id}.part`);
}
function metaPath(id) {
    return path.join(TEMP_DIR, `${id}.json`);
}
function persistSession(session) {
    fs.writeFileSync(metaPath(session.id), JSON.stringify(session));
}
function loadSession(id) {
    const cached = sessions.get(id);
    if (cached)
        return cached;
    if (!sessionIdPattern(id))
        return null;
    try {
        const raw = fs.readFileSync(metaPath(id), 'utf8');
        const parsed = JSON.parse(raw);
        if (!parsed || parsed.id !== id)
            return null;
        sessions.set(id, parsed);
        return parsed;
    }
    catch {
        return null;
    }
}
function verifyOwnership(session, userId) {
    if (session.userId !== userId) {
        throw new UploadSessionError('This upload belongs to a different account', 403);
    }
}
function currentSize(id) {
    try {
        return fs.statSync(partPath(id)).size;
    }
    catch {
        return 0;
    }
}
function removeSessionFiles(id) {
    sessions.delete(id);
    for (const file of [partPath(id), metaPath(id)]) {
        try {
            fs.rmSync(file, { force: true });
        }
        catch {
            // Best effort; stale-file cleanup will retry later.
        }
    }
}
async function freeDiskBytes() {
    const stats = await fs.promises.statfs(UPLOAD_ROOT);
    return Number(stats.bavail) * Number(stats.bsize);
}
function cleanupStaleSessions() {
    try {
        ensureDirs();
        const now = Date.now();
        for (const entry of fs.readdirSync(TEMP_DIR)) {
            const full = path.join(TEMP_DIR, entry);
            try {
                const stats = fs.statSync(full);
                if (now - stats.mtimeMs > SESSION_TTL_MS)
                    fs.rmSync(full, { force: true });
            }
            catch {
                // File disappeared mid-scan.
            }
        }
        for (const [id, session] of sessions) {
            if (now - session.createdAt > SESSION_TTL_MS)
                sessions.delete(id);
        }
    }
    catch (error) {
        console.error('Stale upload cleanup failed:', error);
    }
}
cleanupStaleSessions();
setInterval(cleanupStaleSessions, 60 * 60 * 1000).unref();
export async function startVideoUpload(userId, fileName, fileSize) {
    if (typeof fileName !== 'string' || !fileName.trim()) {
        throw new UploadSessionError('A file name is required');
    }
    const extension = path.extname(fileName).toLowerCase();
    if (!VIDEO_UPLOAD_EXTENSIONS.has(extension)) {
        throw new UploadSessionError('Video must be an MP4, M4V, MOV, WEBM, OGG, or OGV file');
    }
    const declaredSize = Number(fileSize);
    if (!Number.isInteger(declaredSize) || declaredSize <= 0) {
        throw new UploadSessionError('A valid file size is required');
    }
    if (declaredSize > MAX_VIDEO_UPLOAD_BYTES) {
        throw new UploadSessionError(`Video exceeds the ${Math.round(MAX_VIDEO_UPLOAD_BYTES / (1024 ** 3))} GB upload limit`, 413);
    }
    ensureDirs();
    const free = await freeDiskBytes();
    if (free < declaredSize + DISK_HEADROOM_BYTES) {
        throw new UploadSessionError('Not enough free disk space on the server for this video', 507);
    }
    const session = {
        id: crypto.randomUUID(),
        userId,
        fileName: fileName.trim(),
        extension,
        fileSize: declaredSize,
        createdAt: Date.now(),
    };
    fs.writeFileSync(partPath(session.id), Buffer.alloc(0));
    persistSession(session);
    sessions.set(session.id, session);
    return { upload_id: session.id, offset: 0, max_bytes: MAX_VIDEO_UPLOAD_BYTES };
}
export function getVideoUpload(userId, id) {
    const session = requireSession(id);
    verifyOwnership(session, userId);
    return { offset: currentSize(id), file_size: session.fileSize };
}
export async function appendVideoChunk(userId, id, offsetValue, chunk) {
    const session = requireSession(id);
    verifyOwnership(session, userId);
    if (!chunk || chunk.length === 0) {
        throw new UploadSessionError('The uploaded chunk is empty');
    }
    if (chunk.length > MAX_CHUNK_BYTES) {
        throw new UploadSessionError('Upload chunk is too large', 413);
    }
    const offset = Number(offsetValue);
    if (!Number.isInteger(offset) || offset < 0) {
        throw new UploadSessionError('A valid chunk offset is required');
    }
    const size = currentSize(id);
    if (offset !== size) {
        throw new UploadSessionError(`Chunk offset mismatch: expected ${size}, received ${offset}`, 409);
    }
    if (size + chunk.length > session.fileSize) {
        throw new UploadSessionError('Chunk exceeds the declared file size');
    }
    await fs.promises.appendFile(partPath(id), chunk);
    const nextOffset = size + chunk.length;
    return { offset: nextOffset };
}
function looksLikeVideo(filePath, extension) {
    const fd = fs.openSync(filePath, 'r');
    try {
        const header = Buffer.alloc(16);
        const read = fs.readSync(fd, header, 0, header.length, 0);
        if (read < 12)
            return false;
        if (extension === '.webm') {
            return header[0] === 0x1a && header[1] === 0x45 && header[2] === 0xdf && header[3] === 0xa3;
        }
        if (extension === '.ogv' || extension === '.ogg') {
            return header.toString('ascii', 0, 4) === 'OggS';
        }
        return header.toString('ascii', 4, 8) === 'ftyp';
    }
    finally {
        fs.closeSync(fd);
    }
}
export function completeVideoUpload(userId, id) {
    const session = requireSession(id);
    verifyOwnership(session, userId);
    const size = currentSize(id);
    if (size !== session.fileSize) {
        throw new UploadSessionError(`Upload incomplete: received ${size} of ${session.fileSize} bytes`, 400);
    }
    if (!looksLikeVideo(partPath(id), session.extension)) {
        removeSessionFiles(id);
        throw new UploadSessionError('The uploaded file is not a valid video');
    }
    ensureDirs();
    const safeName = safeUploadName(session.fileName, session.extension);
    const destination = path.join(VIDEO_DIR, safeName);
    fs.renameSync(partPath(id), destination);
    removeSessionFiles(id);
    return { video_path: `/uploads/videos/${safeName}` };
}
export function abortVideoUpload(userId, id) {
    const session = loadSession(id);
    if (!session)
        return;
    verifyOwnership(session, userId);
    removeSessionFiles(id);
}
function requireSession(id) {
    if (!sessionIdPattern(id)) {
        throw new UploadSessionError('Unknown upload session', 404);
    }
    const session = loadSession(id);
    if (!session) {
        throw new UploadSessionError('Upload session not found or expired', 404);
    }
    return session;
}
