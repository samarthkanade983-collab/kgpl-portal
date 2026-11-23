import path from 'path';
export class InvalidUploadError extends Error {
}
export const MAX_VIDEO_BYTES = 200 * 1024 * 1024;
export const MAX_SOP_BYTES = 25 * 1024 * 1024;
const VIDEO_EXTENSIONS = new Set(['.mp4', '.m4v', '.mov', '.webm', '.ogv', '.ogg']);
const DOCUMENT_EXTENSIONS = new Set([
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.txt', '.md',
    '.ppt', '.pptx', '.png', '.jpg', '.jpeg', '.gif', '.webp',
]);
const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp']);
function detectImageExtension(buffer) {
    if (buffer.length >= 8 && buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) {
        return true;
    }
    if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
        return true;
    }
    if (buffer.length >= 12 &&
        buffer.toString('ascii', 0, 4) === 'RIFF' &&
        buffer.toString('ascii', 8, 12) === 'WEBP') {
        return true;
    }
    return buffer.length >= 6 && buffer.toString('ascii', 0, 4) === 'GIF8';
}
function looksLikeVideo(buffer, extension) {
    if (buffer.length < 12)
        return false;
    if (extension === '.webm') {
        return buffer[0] === 0x1a && buffer[1] === 0x45 && buffer[2] === 0xdf && buffer[3] === 0xa3;
    }
    if (extension === '.ogv' || extension === '.ogg') {
        return buffer.toString('ascii', 0, 4) === 'OggS';
    }
    // MP4 / M4V / MOV all carry an ISO base-media "ftyp" box near the start.
    return buffer.toString('ascii', 4, 8) === 'ftyp';
}
function looksLikeDocument(buffer, extension) {
    switch (extension) {
        case '.pdf':
            return buffer.toString('ascii', 0, 4) === '%PDF';
        case '.docx':
        case '.xlsx':
        case '.pptx':
            return buffer.length >= 4 && buffer[0] === 0x50 && buffer[1] === 0x4b && buffer[2] === 0x03 && buffer[3] === 0x04;
        case '.doc':
        case '.xls':
        case '.ppt':
            return (buffer.length >= 8 &&
                buffer[0] === 0xd0 && buffer[1] === 0xcf && buffer[2] === 0x11 && buffer[3] === 0xe0 &&
                buffer[4] === 0xa1 && buffer[5] === 0xb1 && buffer[6] === 0x1a && buffer[7] === 0xe1);
        case '.png':
        case '.jpg':
        case '.jpeg':
        case '.gif':
        case '.webp':
            return detectImageExtension(buffer);
        default:
            // Plain-text formats carry no reliable magic bytes.
            return !buffer.subarray(0, 1024).includes(0);
    }
}
export function decodeUpload(fileName, data, kind) {
    if (typeof fileName !== 'string' || !fileName.trim() || typeof data !== 'string' || !data) {
        throw new InvalidUploadError('A file name and file contents are required');
    }
    const extension = path.extname(fileName).toLowerCase();
    const allowed = kind === 'video' ? VIDEO_EXTENSIONS : DOCUMENT_EXTENSIONS;
    if (!allowed.has(extension)) {
        throw new InvalidUploadError(kind === 'video'
            ? 'Video must be an MP4, M4V, MOV, WEBM, OGG, or OGV file'
            : 'Unsupported file type. Allowed: PDF, Word, Excel, PowerPoint, CSV, TXT, MD, and images');
    }
    const cleanBase64 = data.replace(/^data:[^;,]+;base64,/i, '');
    const buffer = Buffer.from(cleanBase64, 'base64');
    if (buffer.length === 0) {
        throw new InvalidUploadError('The uploaded file is empty');
    }
    const maxBytes = kind === 'video' ? MAX_VIDEO_BYTES : MAX_SOP_BYTES;
    if (buffer.length > maxBytes) {
        throw new InvalidUploadError(kind === 'video'
            ? 'Video must be 200 MB or smaller'
            : 'File must be 25 MB or smaller');
    }
    const validContent = kind === 'video' ? looksLikeVideo(buffer, extension) : looksLikeDocument(buffer, extension);
    if (!validContent) {
        throw new InvalidUploadError('The file contents do not match its file extension');
    }
    return { buffer, extension };
}
export function safeUploadName(fileName, extension) {
    const base = path
        .basename(fileName, path.extname(fileName))
        .replace(/[^a-zA-Z0-9._-]/g, '_')
        .replace(/^[._]+/, '')
        .slice(0, 80);
    return `${Date.now()}_${base || 'upload'}${extension}`;
}
export function isVideoUploadPath(requestPath) {
    const normalized = path.posix.normalize(requestPath.replace(/\\/g, '/')).toLowerCase();
    return normalized.startsWith('/videos/') ||
        VIDEO_EXTENSIONS.has(path.extname(normalized)) ||
        ['.avi', '.mkv'].includes(path.extname(normalized));
}
export function isInlineSafeUploadPath(requestPath) {
    const extension = path.extname(requestPath).toLowerCase();
    return (IMAGE_EXTENSIONS.has(extension) ||
        extension === '.pdf' ||
        VIDEO_EXTENSIONS.has(extension) ||
        extension === '.mp3' ||
        extension === '.wav');
}
