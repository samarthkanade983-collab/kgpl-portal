import fs from 'fs';
import path from 'path';

const readBoxHeader = (fd: number, position: number, fileSize: number) => {
  const header = Buffer.alloc(16);
  const read = fs.readSync(fd, header, 0, 16, position);
  if (read < 8) return null;
  let size = header.readUInt32BE(0);
  const type = header.slice(4, 8).toString('latin1');
  let headerSize = 8;
  if (size === 1 && read >= 16) {
    size = Number(header.readBigUInt64BE(8));
    headerSize = 16;
  } else if (size === 0) {
    size = fileSize - position;
  }
  if (!Number.isFinite(size) || size < headerSize) return null;
  return { size, type, headerSize, contentStart: position + headerSize, contentSize: size - headerSize };
};

const readRange = (fd: number, start: number, length: number) => {
  const buffer = Buffer.alloc(length);
  const read = fs.readSync(fd, buffer, 0, length, start);
  return buffer.slice(0, read);
};

function probeIsoBmff(fd: number, fileSize: number): number | null {
  let position = 0;
  let moov: { contentStart: number; contentSize: number } | null = null;

  while (position + 8 <= fileSize) {
    const box = readBoxHeader(fd, position, fileSize);
    if (!box) break;
    if (box.type === 'moov') {
      moov = { contentStart: box.contentStart, contentSize: box.contentSize };
      break;
    }
    position += box.size;
  }

  if (!moov) return null;

  const window = Math.min(moov.contentSize, 4 * 1024 * 1024);
  const data = readRange(fd, moov.contentStart, window);
  let offset = 0;
  while (offset + 8 <= data.length) {
    let size = data.readUInt32BE(offset);
    const type = data.slice(offset + 4, offset + 8).toString('latin1');
    let headerSize = 8;
    if (size === 1 && offset + 16 <= data.length) {
      size = Number(data.readBigUInt64BE(offset + 8));
      headerSize = 16;
    }
    if (!Number.isFinite(size) || size < headerSize) break;

    if (type === 'mvhd') {
      const body = data.slice(offset + headerSize, Math.min(offset + size, data.length));
      if (body.length < 20) return null;
      const version = body[0];
      const timescale = version === 1 ? body.readUInt32BE(20) : body.readUInt32BE(12);
      const duration = version === 1 ? Number(body.readBigUInt64BE(24)) : body.readUInt32BE(16);
      if (!timescale) return null;
      const seconds = duration / timescale;
      return seconds > 0 && seconds < 24 * 60 * 60 ? seconds : null;
    }
    offset += size;
  }
  return null;
}

export function probeVideoDurationSeconds(filePath: string): number | null {
  let fd: number | null = null;
  try {
    if (!fs.existsSync(filePath)) return null;
    const fileSize = fs.statSync(filePath).size;
    if (fileSize < 32) return null;
    fd = fs.openSync(filePath, 'r');
    const head = Buffer.alloc(8);
    fs.readSync(fd, head, 0, 8, 0);
    const type = head.slice(4, 8).toString('latin1');
    if (type === 'ftyp') return probeIsoBmff(fd, fileSize);
    return null;
  } catch {
    return null;
  } finally {
    if (fd !== null) {
      try {
        fs.closeSync(fd);
      } catch {
        // Closing a read handle can only fail if it was already closed.
      }
    }
  }
}

export function resolveStoredVideoDuration(
  videoPath: string | null | undefined,
  fallbackSeconds?: unknown
): number {
  if (videoPath && videoPath.startsWith('/uploads/')) {
    const absolute = path.resolve(videoPath.replace(/^\/+/, ''));
    const probed = probeVideoDurationSeconds(absolute);
    if (probed) return Math.max(1, Math.floor(probed));
  }
  const fallback = Number(fallbackSeconds);
  return Number.isFinite(fallback) && fallback > 0 ? Math.round(fallback) : 600;
}
