import { Request } from 'express';
import { pool } from '../config/db.js';

export async function logAuditEvent(
  userId: number | null,
  action: string,
  entityType?: string,
  entityId?: number,
  oldValues?: any,
  newValues?: any,
  req?: Request
): Promise<void> {
  try {
    const ip = req?.ip || req?.socket.remoteAddress || '127.0.0.1';
    const userAgent = req?.headers['user-agent'] || 'KGPL Client';

    await pool.query(
      `INSERT INTO audit_logs 
        (user_id, action, entity_type, entity_id, old_values, new_values, ip_address, user_agent, created_at, updated_at) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`,
      [
        userId,
        action,
        entityType || null,
        entityId || null,
        oldValues ? JSON.stringify(oldValues) : null,
        newValues ? JSON.stringify(newValues) : null,
        ip,
        userAgent,
      ]
    );
  } catch (error) {
    console.error('Failed to write audit log:', error);
  }
}
