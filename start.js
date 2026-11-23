import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WATCH = process.argv.includes('--watch');
const API_PORT = Number(process.env.API_PORT || process.env.BACKEND_PORT || 5001);
const WEB_PORT = Number(process.env.WEB_PORT || process.env.PORT || 3002);
const OPEN_BROWSER = process.env.OPEN_BROWSER !== '0';
const API_DIR = path.join(__dirname, 'backend');
const WEB_DIR = path.join(__dirname, 'frontend');
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const children = [];
let shuttingDown = false;

const [nodeMajor, nodeMinor] = process.versions.node.split('.').map(Number);
if (nodeMajor < 20 || (nodeMajor === 20 && nodeMinor < 19)) {
  console.error(`Node 20.19 or newer is required. This machine has ${process.versions.node}.`);
  process.exit(1);
}

function pipeWithLabel(stream, label, out) {
  let buffer = '';
  stream.setEncoding('utf8');
  stream.on('data', (chunk) => {
    buffer += chunk;
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
      out.write(`[${label}] ${buffer.slice(0, index)}\n`);
      buffer = buffer.slice(index + 1);
    }
  });
  stream.on('end', () => {
    if (buffer.trim()) out.write(`[${label}] ${buffer}\n`);
  });
}

function run(label, args, cwd, env) {
  const child = spawn(process.execPath, args, {
    cwd,
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  pipeWithLabel(child.stdout, label, process.stdout);
  pipeWithLabel(child.stderr, label, process.stderr);
  child.on('exit', (code) => {
    if (!shuttingDown) console.log(`[${label}] stopped with code ${code}`);
  });
  children.push(child);
  return child;
}

function installDependencies() {
  const command =
    process.platform === 'win32'
      ? ['cmd.exe', ['/d', '/s', '/c', 'npm install --no-audit --no-fund']]
      : ['npm', ['install', '--no-audit', '--no-fund']];
  console.log('[api] first run, installing dependencies (this takes a minute)...');
  return new Promise((resolve) => {
    const child = spawn(command[0], command[1], {
      cwd: API_DIR,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    pipeWithLabel(child.stdout, 'npm', process.stdout);
    pipeWithLabel(child.stderr, 'npm', process.stderr);
    child.on('error', (error) => {
      console.log(`[api] dependency install failed: ${error.message}`);
      resolve(false);
    });
    child.on('exit', (code) => {
      if (code === 0) console.log('[api] dependencies installed');
      resolve(code === 0);
    });
  });
}

async function ensureDependencies() {
  if (fs.existsSync(path.join(API_DIR, 'node_modules', 'tsx'))) return true;
  return installDependencies();
}

async function isUp(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(1500) });
    return response.ok;
  } catch {
    return false;
  }
}

async function waitFor(url, label, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let attempts = 0;
  while (Date.now() < deadline) {
    if (await isUp(url)) return true;
    attempts += 1;
    if (label === 'api' && children.length && children[0].exitCode !== null) return false;
    await sleep(400);
  }
  console.log(`[${label}] did not respond within ${Math.round(timeoutMs / 1000)}s`);
  return false;
}

function openBrowser(url) {
  if (!OPEN_BROWSER) return;
  const [command, args] =
    process.platform === 'win32'
      ? ['cmd.exe', ['/c', 'start', '', url]]
      : process.platform === 'darwin'
        ? ['open', [url]]
        : ['xdg-open', [url]];
  try {
    const opener = spawn(command, args, { stdio: 'ignore', detached: true });
    opener.unref();
  } catch {
    console.log('Open this address in your browser:', url);
  }
}

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log('Stopping the portal...');
  for (const child of children) {
    if (child.exitCode === null) child.kill('SIGTERM');
  }
  setTimeout(() => {
    for (const child of children) {
      if (child.exitCode === null) child.kill('SIGKILL');
    }
    process.exit(0);
  }, 2500).unref();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

console.log('=======================================================');
console.log(' KGPL Portal - starting the API and the web portal together');
console.log(` API    -> http://localhost:${API_PORT}`);
console.log(` Portal -> http://localhost:${WEB_PORT}`);
console.log(' Press Ctrl+C to stop everything.');
console.log('=======================================================');

if (await isUp(`http://127.0.0.1:${API_PORT}/health`)) {
  console.log(`[api] already running on port ${API_PORT}, using it`);
} else if (!(await ensureDependencies())) {
  console.error('[api] cannot start without installed dependencies. Check the lines above.');
  process.exitCode = 1;
} else {
  const backendArgs = WATCH
    ? ['--import', 'tsx', '--watch', 'src/server.ts']
    : ['--import', 'tsx', 'src/server.ts'];
  run('api', backendArgs, API_DIR, { PORT: String(API_PORT) });
  if (!(await waitFor(`http://127.0.0.1:${API_PORT}/health`, 'api', 30000))) {
    process.exitCode = 1;
  }
}

if (await isUp(`http://127.0.0.1:${WEB_PORT}/`)) {
  console.log(`[web] already running on port ${WEB_PORT}`);
  openBrowser(`http://localhost:${WEB_PORT}`);
} else {
  run('web', ['serve.js'], WEB_DIR, {
    PORT: String(WEB_PORT),
    BACKEND_PORT: String(API_PORT),
  });
  if (await waitFor(`http://127.0.0.1:${WEB_PORT}/`, 'web', 15000)) {
    openBrowser(`http://localhost:${WEB_PORT}`);
  } else {
    process.exitCode = 1;
  }
}

if (children.length === 0) {
  console.log('Both services are already running, nothing to start.');
  process.exit(0);
}
