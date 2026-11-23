import './config/env.js';
import express from 'express';
import cors from 'cors';
import fs from 'fs';
import path from 'path';
import { testConnection } from './config/db.js';
import { connectMongo, isMongoLive } from './config/mongodb.js';
import apiRouter from './routes/api.js';
import { isInlineSafeUploadPath } from './utils/upload.js';
import { ensureCertificateTable } from './utils/certificate.js';
import { ensureTaskAssignmentsTable } from './utils/taskAssignment.js';
import { ensureCourseModuleTestTables } from './utils/courseModuleTests.js';
import { protectVideoUpload } from './middleware/auth.js';

const app = express();
const PORT = process.env.PORT || 5000;

app.disable('x-powered-by');

// Baseline security headers for every API response
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  const isApiPath = req.path.startsWith('/api/') || req.path.startsWith('/uploads/') || req.path === '/health';
  res.setHeader(
    'Content-Security-Policy',
    isApiPath
      ? "default-src 'none'; frame-ancestors 'none'"
      // Flutter web portal: needs wasm, inline styles, blob/data URLs and https assets (fonts, CanvasKit).
      : "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'unsafe-inline' https://www.gstatic.com; " +
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' data: https://fonts.gstatic.com https://www.gstatic.com; " +
        "img-src 'self' data: blob: https:; media-src 'self' blob: data: https:; connect-src 'self' data: blob: https://www.gstatic.com https://fonts.gstatic.com; " +
        "worker-src 'self' blob:; frame-ancestors 'none'",
  );
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  // Uploaded media is embedded by the portal, which runs on another port.
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  res.setHeader('X-Permitted-Cross-Domain-Policies', 'none');
  res.setHeader('X-DNS-Prefetch-Control', 'off');
  res.setHeader('Origin-Agent-Cluster', '?1');
  if (req.path.startsWith('/api/') || req.path === '/health') {
    res.setHeader('Cache-Control', 'no-store');
  }
  next();
});

// Only browser origins listed in CORS_ORIGINS may call the API cross-origin
const allowedOrigins = (process.env.CORS_ORIGINS || 'http://localhost:3000,http://127.0.0.1:3000,http://localhost:3001,http://127.0.0.1:3001,http://localhost:3002,http://127.0.0.1:3002')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

app.use(cors({
  origin: allowedOrigins,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Accept'],
  maxAge: 600,
  optionsSuccessStatus: 204,
}));

// Body parsers (allow large files / PDFs / Excel / Photos encoded in base64)
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));

// Static file serving for uploads (SOP documents, images, PDFs, Excel sheets).
// Anything that is not media or a PDF is forced to download so an uploaded
// HTML/SVG/JS file can never execute in the portal's origin.
app.use(
  '/uploads',
  protectVideoUpload,
  (req, res, next) => {
    if (!isInlineSafeUploadPath(req.path)) {
      res.setHeader('Content-Type', 'application/octet-stream');
      res.setHeader('Content-Disposition', 'attachment');
    }
    next();
  },
  express.static(path.resolve('uploads'), {
    dotfiles: 'deny',
    index: false,
  })
);

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    if (req.originalUrl !== '/health') {
      console.log(`[${new Date().toISOString()}] ${req.method} ${req.path} - ${res.statusCode} (${duration}ms)`);
    }
  });
  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'online', mongo: isMongoLive() ? 'live' : 'fallback' });
});

// Mount V1 API Routes
app.use('/api/v1', apiRouter);

// Static Web Portal serving (Unified single-service deployment on Render / Cloud)
const possibleWebPaths = [
  path.resolve('../frontend/build/web'),
  path.resolve('frontend/build/web'),
  path.resolve(process.cwd(), '../frontend/build/web'),
  path.resolve(process.cwd(), 'frontend/build/web'),
];
const webDistPath = possibleWebPaths.find((p) => fs.existsSync(path.join(p, 'index.html')));

if (webDistPath) {
  console.log(`🌐 Serving Web Portal from: ${webDistPath}`);
  app.use(express.static(webDistPath, {
    index: 'index.html',
    setHeaders: (res, filePath) => {
      if (filePath.endsWith('.html') || filePath.endsWith('.js') || filePath.endsWith('.json')) {
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      }
    },
  }));

  // SPA fallback for non-API routes
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api/') || req.path.startsWith('/uploads/') || req.path === '/health') {
      return next();
    }
    res.sendFile(path.join(webDistPath, 'index.html'));
  });
}

// 404 handler for unmatched API routes
app.use((req, res) => {
  res.status(404).json({ error: `Route not found: ${req.method} ${req.originalUrl}` });
});

// Global Error Handler
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  // Client aborted request (e.g. video scrub/close or tab switch) - safe to ignore
  if (err?.code === 'ECONNABORTED' || err?.message === 'Request aborted') {
    return;
  }
  console.error('Unhandled server error:', err);
  if (res.headersSent) {
    next(err);
    return;
  }
  const status = Number(err?.status || err?.statusCode) || 500;
  if (status >= 400 && status < 500) {
    res.status(status).json({ error: status === 413 ? 'Request payload too large' : 'Invalid request' });
    return;
  }
  res.status(500).json({ error: 'Internal Server Error' });
});

// Start server
process.on('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection:', reason);
});

async function bootstrap() {
  await testConnection();
  await ensureCertificateTable();
  await ensureTaskAssignmentsTable();
  await ensureCourseModuleTestTables();
  await connectMongo();
  app.listen(Number(PORT), '0.0.0.0', () => {
    console.log(`🚀 KGPL Modern REST API is live on http://localhost:${PORT}`);
    console.log(`📊 Health check: http://localhost:${PORT}/health`);
    console.log(`🔑 API Base URL: http://localhost:${PORT}/api/v1`);
  });
}

bootstrap().catch((err) => {
  console.error('Bootstrap failed:', err);
  process.exit(1);
});
