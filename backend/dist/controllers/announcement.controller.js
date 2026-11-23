import { pool } from '../config/db.js';
const NOT_EXPIRED = '(a.expires_at IS NULL OR a.expires_at > NOW())';
export async function getActiveAnnouncements(req, res) {
    const user = req.user;
    try {
        let rows;
        if (user.role === 'hr_admin') {
            [rows] = await pool.query(`SELECT a.*, u.name AS author_name
         FROM announcements a
         LEFT JOIN users u ON a.author_id = u.id
         WHERE ${NOT_EXPIRED}
         ORDER BY a.created_at DESC
         LIMIT 50`);
        }
        else if (user.role === 'team_leader') {
            [rows] = await pool.query(`SELECT a.*, u.name AS author_name
         FROM announcements a
         LEFT JOIN users u ON a.author_id = u.id
         WHERE ${NOT_EXPIRED}
           AND (a.is_global = 1
                OR a.target_department_id IN (
                     SELECT DISTINCT ip.department_id FROM intern_profiles ip
                     WHERE ip.assigned_team_leader_id = ? AND ip.department_id IS NOT NULL)
                OR a.target_batch_id IN (
                     SELECT DISTINCT ip.batch_id FROM intern_profiles ip
                     WHERE ip.assigned_team_leader_id = ? AND ip.batch_id IS NOT NULL))
         ORDER BY a.created_at DESC
         LIMIT 50`, [user.id, user.id]);
        }
        else {
            [rows] = await pool.query(`SELECT a.*, u.name AS author_name
         FROM announcements a
         LEFT JOIN users u ON a.author_id = u.id
         WHERE ${NOT_EXPIRED}
           AND (a.is_global = 1
                OR a.target_batch_id = (SELECT ip.batch_id FROM intern_profiles ip WHERE ip.user_id = ?)
                OR a.target_department_id = (SELECT ip.department_id FROM intern_profiles ip WHERE ip.user_id = ?))
         ORDER BY a.created_at DESC
         LIMIT 50`, [user.id, user.id]);
        }
        res.json({ announcements: rows });
    }
    catch (error) {
        console.error('Get active announcements error:', error);
        res.status(500).json({ error: 'Failed to fetch announcements' });
    }
}
export async function getMyNotifications(req, res) {
    try {
        const [rows] = await pool.query(`SELECT id, title, message, action_url, is_read, read_at, created_at
       FROM notifications
       WHERE user_id = ?
       ORDER BY created_at DESC
       LIMIT 50`, [req.user.id]);
        const [countRows] = await pool.query('SELECT COUNT(*) AS unread FROM notifications WHERE user_id = ? AND is_read = 0', [req.user.id]);
        res.json({ notifications: rows, unread_count: countRows[0].unread });
    }
    catch (error) {
        console.error('Get notifications error:', error);
        res.status(500).json({ error: 'Failed to fetch notifications' });
    }
}
export async function markNotificationsRead(req, res) {
    const { ids } = req.body || {};
    try {
        if (Array.isArray(ids) && ids.length > 0) {
            const numericIds = ids.map((v) => Number(v)).filter((v) => Number.isInteger(v) && v > 0);
            if (numericIds.length > 0) {
                await pool.query('UPDATE notifications SET is_read = 1, read_at = NOW(), updated_at = NOW() WHERE user_id = ? AND id IN (?)', [req.user.id, numericIds]);
            }
        }
        else {
            await pool.query('UPDATE notifications SET is_read = 1, read_at = NOW(), updated_at = NOW() WHERE user_id = ? AND is_read = 0', [req.user.id]);
        }
        res.json({ message: 'Notifications marked as read' });
    }
    catch (error) {
        console.error('Mark notifications read error:', error);
        res.status(500).json({ error: 'Failed to mark notifications as read' });
    }
}
export async function fanOutAnnouncementNotifications(announcementId, authorId, title, content, isGlobal, targetBatchId, targetDepartmentId) {
    await pool.query(`INSERT INTO notifications (user_id, title, message, action_url, is_read, created_at, updated_at)
     SELECT u.id, ?, ?, ?, 0, NOW(), NOW()
     FROM users u
     LEFT JOIN intern_profiles ip ON u.id = ip.user_id
     WHERE u.deleted_at IS NULL AND u.is_active = 1
       AND u.role IN ('intern', 'team_leader')
       AND u.id <> ?
       AND (? = 1
            OR (u.role = 'intern'
                AND (? IS NULL OR ip.batch_id = ?)
                AND (? IS NULL OR ip.department_id = ?))
            OR (u.role = 'team_leader'
                AND EXISTS (SELECT 1 FROM intern_profiles ip2
                            WHERE ip2.assigned_team_leader_id = u.id
                              AND (? IS NULL OR ip2.batch_id = ?)
                              AND (? IS NULL OR ip2.department_id = ?))))`, [
        `Announcement: ${title}`,
        content,
        `announcement:${announcementId}`,
        authorId,
        isGlobal ? 1 : 0,
        targetBatchId, targetBatchId,
        targetDepartmentId, targetDepartmentId,
        targetBatchId, targetBatchId,
        targetDepartmentId, targetDepartmentId,
    ]);
}
