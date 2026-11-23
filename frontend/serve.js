import http from 'http';
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const [nodeMajor, nodeMinor] = process.versions.node.split('.').map(Number);
if (nodeMajor < 20 || (nodeMajor === 20 && nodeMinor < 19)) {
  console.error(`Node 20.19 or newer is required. This machine has ${process.versions.node}.`);
  process.exit(1);
}

const PORT = Number(process.env.PORT || 3000);
const BACKEND_PORT = Number(process.env.BACKEND_PORT || 5001);
const HOST = '0.0.0.0';
const PUBLIC_DIR = path.join(__dirname, 'build', 'web');

const MIME_TYPES = {
  '.html': 'text/html; charset=UTF-8',
  '.js': 'application/javascript; charset=UTF-8',
  '.mjs': 'application/javascript; charset=UTF-8',
  '.json': 'application/json; charset=UTF-8',
  '.css': 'text/css; charset=UTF-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.mp4': 'video/mp4',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'SAMEORIGIN',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'geolocation=(), microphone=(), camera=()',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'X-Permitted-Cross-Domain-Policies': 'none',
  'X-DNS-Prefetch-Control': 'off',
};

const API_HOSTS = BACKEND_PORT === 5001
  ? `http://localhost:5001 http://127.0.0.1:5001`
  : `http://localhost:${BACKEND_PORT} http://127.0.0.1:${BACKEND_PORT} http://localhost:5001 http://127.0.0.1:5001`;

const APP_CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob: https://www.gstatic.com",
  "style-src 'self' 'unsafe-inline'",
  `img-src 'self' data: blob: ${API_HOSTS}`,
  `media-src 'self' blob: data: ${API_HOSTS}`,
  `connect-src 'self' ${API_HOSTS} https://www.gstatic.com https://fonts.gstatic.com`,
  "font-src 'self' data: https://fonts.gstatic.com",
  "worker-src 'self' blob:",
  "frame-ancestors 'self'",
].join('; ');

// The web server also owns the API process so one command runs the whole portal.
// Set AUTO_BACKEND=0 to keep the API managed separately.
const AUTO_BACKEND = process.env.AUTO_BACKEND !== '0';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let backendChild = null;
let shuttingDown = false;

function logBackendStream(stream) {
  let buffer = '';
  stream.setEncoding('utf8');
  stream.on('data', (chunk) => {
    buffer += chunk;
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
      console.log(`[api] ${buffer.slice(0, index)}`);
      buffer = buffer.slice(index + 1);
    }
  });
  stream.on('end', () => {
    if (buffer.trim()) console.log(`[api] ${buffer}`);
  });
}

async function backendIsUp() {
  try {
    const response = await fetch(`http://127.0.0.1:${BACKEND_PORT}/health`, {
      signal: AbortSignal.timeout(1500),
    });
    return response.ok;
  } catch {
    return false;
  }
}

function installBackendDependencies(backendDir) {
  const [command, args] = process.platform === 'win32'
    ? ['cmd.exe', ['/d', '/s', '/c', 'npm install --no-audit --no-fund']]
    : ['npm', ['install', '--no-audit', '--no-fund']];
  console.log('[api] first run, installing dependencies (this takes a minute)...');
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd: backendDir, stdio: ['ignore', 'pipe', 'pipe'] });
    logBackendStream(child.stdout);
    logBackendStream(child.stderr);
    child.on('error', (error) => {
      console.warn(`[api] dependency install failed: ${error.message}`);
      resolve(false);
    });
    child.on('exit', (code) => {
      if (code === 0) console.log('[api] dependencies installed');
      resolve(code === 0);
    });
  });
}

async function ensureBackend() {
  if (!AUTO_BACKEND) return;
  if (await backendIsUp()) {
    console.log(`[api] already running on port ${BACKEND_PORT}`);
    return;
  }
  const backendDir = path.join(__dirname, '..', 'backend');
  if (!fs.existsSync(path.join(backendDir, 'src', 'server.ts'))) {
    console.warn('[api] backend not found, start it separately');
    return;
  }
  if (!fs.existsSync(path.join(backendDir, 'node_modules', 'tsx'))) {
    if (!(await installBackendDependencies(backendDir))) {
      console.warn('[api] cannot start without installed dependencies');
      return;
    }
  }
  backendChild = spawn(process.execPath, ['--import', 'tsx', 'src/server.ts'], {
    cwd: backendDir,
    env: { ...process.env, PORT: String(BACKEND_PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  logBackendStream(backendChild.stdout);
  logBackendStream(backendChild.stderr);
  backendChild.on('exit', (code) => {
    backendChild = null;
    if (!shuttingDown) console.warn(`[api] stopped with code ${code}`);
  });
  for (let attempt = 0; attempt < 60; attempt += 1) {
    if (await backendIsUp()) {
      console.log(`[api] started on port ${BACKEND_PORT}`);
      return;
    }
    if (!backendChild) return;
    await sleep(500);
  }
  console.warn('[api] did not become ready in time, check the lines above');
}

function stopBackend() {
  shuttingDown = true;
  if (backendChild) {
    backendChild.kill('SIGTERM');
    backendChild = null;
  }
}

process.on('SIGINT', () => {
  stopBackend();
  process.exit(0);
});
process.on('SIGTERM', () => {
  stopBackend();
  process.exit(0);
});

const server = http.createServer((req, res) => {
  const start = Date.now();
  const cleanUrl = req.url.split('?')[0];

  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    res.setHeader(name, value);
  }

  // Replace Flutter's cache-first service worker with a self-unregistering stub
  // so stale cached bundles can never survive a reload on this dev portal.
  if (cleanUrl === '/flutter_service_worker.js') {
    res.writeHead(200, {
      'Content-Type': 'application/javascript; charset=UTF-8',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Access-Control-Allow-Origin': '*',
      'Service-Worker-Allowed': '/',
    });
    res.end(`
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    const hadStaleCache = keys.length > 0;
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.clients.claim();
    const clients = await self.clients.matchAll({ type: 'window' });
    await self.registration.unregister();
    if (hadStaleCache) await Promise.all(clients.map((c) => c.navigate(c.url).catch(() => {})));
  })());
});
`);
    return;
  }

  // Proxy API and upload requests directly to the Express backend
  if (req.url.startsWith('/api/') || req.url.startsWith('/uploads/') || req.url === '/health') {
    const proxyReq = http.request({
      hostname: '127.0.0.1',
      port: BACKEND_PORT,
      path: req.url,
      method: req.method,
      headers: { ...req.headers, host: `127.0.0.1:${BACKEND_PORT}` },
    }, (proxyRes) => {
      // Pass the backend's own CORS/security headers through unchanged.
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', (err) => {
      console.error(`[Proxy Error] ${req.method} ${cleanUrl} ->`, err.message);
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Backend gateway connection failed', message: err.message }));
    });

    req.pipe(proxyReq);
    return;
  }

  // Handle CORS preflight for SPA
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Allow': 'GET, HEAD, OPTIONS',
    });
    res.end();
    return;
  }

  // The static frontend only serves GET/HEAD; reject diagnostic verbs
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Allow': 'GET, HEAD, OPTIONS' });
    res.end();
    return;
  }

  let safePath;
  try {
    safePath = path.normalize(decodeURIComponent(cleanUrl)).replace(/^(\.\.[\/\\])+/, '');
  } catch {
    res.writeHead(400, { 'Content-Type': 'text/plain' });
    res.end('400 - Bad Request');
    return;
  }
  let filePath = path.join(PUBLIC_DIR, safePath);
  const resolvedPath = path.resolve(filePath);
  if (resolvedPath !== path.resolve(PUBLIC_DIR) &&
      !resolvedPath.startsWith(path.resolve(PUBLIC_DIR) + path.sep)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('403 - Forbidden');
    return;
  }

  // If root or directory, serve index.html
  if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, 'index.html');
  }

  // SPA fallback for HTML routes
  if (!fs.existsSync(filePath)) {
    filePath = path.join(PUBLIC_DIR, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      console.error(`[${new Date().toISOString()}] 500 ERROR: ${req.url} -> ${filePath}`);
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('500 - Internal Server Error');
      return;
    }

    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Security-Policy': APP_CSP,
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    });
    res.end(req.method === 'HEAD' ? undefined : content);
    const duration = Date.now() - start;
    console.log(`[${new Date().toISOString()}] ${req.method} ${cleanUrl} -> 200 (${duration}ms)`);
  });
});

await ensureBackend();

server.listen(PORT, HOST, () => {
  console.log(`=======================================================`);
  console.log(`🌐 KGPL Flutter Web UI is LIVE on:`);
  console.log(`   👉 http://localhost:${PORT}`);
  console.log(`   👉 http://127.0.0.1:${PORT}`);
  console.log(`🔗 Serving from: ${PUBLIC_DIR}`);
  console.log(`=======================================================`);
});
