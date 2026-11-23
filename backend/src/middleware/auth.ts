import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { pool } from '../config/db.js';
import { isVideoUploadPath } from '../utils/upload.js';

export const JWT_SECRET = process.env.JWT_SECRET || 'kgpl_portal_production_jwt_secret_key_2026_secured';

export interface AuthUser {
  id: number;
  name: string;
  email: string;
  role: 'hr_admin' | 'team_leader' | 'intern';
  is_active: boolean;
  profile_photo_path: string | null;
  address: string | null;
  contact_number: string | null;
}

export interface AuthenticatedRequest extends Request {
  user?: AuthUser;
}

export async function authenticateToken(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : null;

  if (!token) {
    res.status(401).json({ error: 'Authentication token required' });
    return;
  }

  try {
    const payload = jwt.verify(token, JWT_SECRET, { algorithms: ['HS256'] }) as { id: number };

    const [rows]: any = await pool.query(
      `SELECT id, name, email, role, is_active, profile_photo_path, address, contact_number
       FROM users WHERE id = ? AND deleted_at IS NULL`,
      [payload.id]
    );

    if (rows.length === 0) {
      res.status(401).json({ error: 'User account not found' });
      return;
    }

    const user = rows[0] as AuthUser;

    if (!user.is_active) {
      res.status(403).json({ error: 'Your account has been deactivated. Please contact HR.' });
      return;
    }

    req.user = user;
    next();
  } catch (error) {
    res.status(403).json({ error: 'Invalid or expired authentication token' });
  }
}

export function protectVideoUpload(req: AuthenticatedRequest, res: Response, next: NextFunction): void {
  let requestPath: string;
  try {
    requestPath = decodeURIComponent(req.path);
  } catch {
    res.status(400).json({ error: 'Invalid upload path' });
    return;
  }
  if (requestPath.includes(':') || requestPath.split(/[\\/]/).some((segment) =>
      segment !== '.' && segment !== '..' && /[. ]$/.test(segment))) {
    res.status(400).json({ error: 'Invalid upload path' });
    return;
  }
  if (!isVideoUploadPath(requestPath)) {
    next();
    return;
  }
  res.setHeader('Cache-Control', 'private, no-store');
  authenticateToken(req, res, () => requireRole(['hr_admin', 'team_leader'])(req, res, next));
}

export function requireRole(allowedRoles: Array<'hr_admin' | 'team_leader' | 'intern'>) {
  return (req: AuthenticatedRequest, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    if (!allowedRoles.includes(req.user.role)) {
      res.status(403).json({
        error: `Access forbidden: Requires one of [${allowedRoles.join(', ')}] role`,
      });
      return;
    }

    next();
  };
}
