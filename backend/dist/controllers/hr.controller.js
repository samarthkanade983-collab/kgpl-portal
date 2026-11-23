import fs from 'fs';
import path from 'path';
import bcrypt from 'bcryptjs';
import { pool } from '../config/db.js';
import { getMongoCollection } from '../config/mongodb.js';
import { logAuditEvent } from '../middleware/audit.js';
import { fanOutAnnouncementNotifications } from './announcement.controller.js';
import { resolveStoredVideoDuration } from '../utils/videoDuration.js';
import { decodeUpload, InvalidUploadError, safeUploadName } from '../utils/upload.js';
import { buildDefaultCertificate, defaultSerial, mergeCertificate } from '../utils/certificate.js';
const PROFILE_PHOTO_DIR = path.resolve('uploads', 'profiles');
const MAX_PROFILE_PHOTO_BYTES = 2 * 1024 * 1024;
const DEFAULT_PASSWORD = 'Password@123';
const PASSWORD_POLICY_MESSAGE = 'Password must be at least 8 characters and contain both letters and numbers';
class InvalidProfilePhotoError extends Error {
}
function meetsPasswordPolicy(value) {
    return typeof value === 'string' && value.length >= 8 && /[A-Za-z]/.test(value) && /[0-9]/.test(value);
}
function parsePositiveInt(value) {
    const num = Number(value);
    return Number.isInteger(num) && num > 0 ? num : null;
}
function detectImageExtension(buffer) {
    if (buffer.length >= 8 && buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) {
        return 'png';
    }
    if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
        return 'jpg';
    }
    if (buffer.length >= 12 &&
        buffer.toString('ascii', 0, 4) === 'RIFF' &&
        buffer.toString('ascii', 8, 12) === 'WEBP') {
        return 'webp';
    }
    if (buffer.length >= 6 && buffer.toString('ascii', 0, 4) === 'GIF8') {
        return 'gif';
    }
    return null;
}
function saveProfilePhoto(base64Input, userId) {
    const raw = base64Input.replace(/^data:[^;,]+;base64,/i, '');
    const buffer = Buffer.from(raw, 'base64');
    if (!buffer.length) {
        throw new InvalidProfilePhotoError('Profile photo must be a valid image under 2 MB');
    }
    if (buffer.length > MAX_PROFILE_PHOTO_BYTES) {
        throw new InvalidProfilePhotoError('Profile photo must be under 2 MB');
    }
    const ext = detectImageExtension(buffer);
    if (!ext) {
        throw new InvalidProfilePhotoError('Profile photo must be a PNG, JPEG, WEBP, or GIF image');
    }
    if (!fs.existsSync(PROFILE_PHOTO_DIR)) {
        fs.mkdirSync(PROFILE_PHOTO_DIR, { recursive: true });
    }
    const fileName = `user-${userId}-${Date.now()}.${ext}`;
    fs.writeFileSync(path.join(PROFILE_PHOTO_DIR, fileName), buffer);
    return `/uploads/profiles/${fileName}`;
}
function deleteProfilePhotoFile(photoPath) {
    if (!photoPath || !photoPath.startsWith('/uploads/profiles/'))
        return;
    const absolute = path.resolve('uploads', 'profiles', path.basename(photoPath));
    if (fs.existsSync(absolute)) {
        try {
            fs.unlinkSync(absolute);
        }
        catch (_) {
            // Leaving an orphan file is harmless; keep the user update intact.
        }
    }
}
// -----------------------------------------------------------------------------
// HR DASHBOARD METRICS
// -----------------------------------------------------------------------------
export async function getDashboardMetrics(req, res) {
    try {
        const [totalInternsRows] = await pool.query("SELECT COUNT(*) AS total FROM users WHERE role = 'intern' AND deleted_at IS NULL");
        const [activeInternsRows] = await pool.query("SELECT COUNT(*) AS total FROM users WHERE role = 'intern' AND is_active = 1 AND deleted_at IS NULL");
        const [totalTeamLeadersRows] = await pool.query("SELECT COUNT(*) AS total FROM users WHERE role = 'team_leader' AND deleted_at IS NULL");
        const [totalCoursesRows] = await pool.query('SELECT COUNT(*) AS total FROM courses');
        // Training completion is derived from real progress inside each intern's own
        // department: every video lesson watched, every SOP / study material read, and
        // no scheduled test left unpassed. This is the same rule that unlocks certificates.
        const [trainingRows] = await pool.query(`SELECT ip.user_id,
              (SELECT COUNT(DISTINCT v.id) FROM videos v
                 JOIN course_modules cm ON v.module_id = cm.id
                 JOIN courses c ON cm.course_id = c.id
                 WHERE c.department_id = ip.department_id AND c.is_published = 1) AS total_videos,
              (SELECT COUNT(DISTINCT v.id) FROM videos v
                 JOIN course_modules cm ON v.module_id = cm.id
                 JOIN courses c ON cm.course_id = c.id
                 JOIN video_watch_logs vwl ON vwl.video_id = v.id AND vwl.user_id = ip.user_id AND vwl.is_completed = 1
                 WHERE c.department_id = ip.department_id AND c.is_published = 1) AS completed_videos,
              (SELECT COUNT(DISTINCT lm.id) FROM learning_materials lm
                 JOIN course_modules cm ON lm.module_id = cm.id
                 JOIN courses c ON cm.course_id = c.id
                 WHERE c.department_id = ip.department_id AND c.is_published = 1) AS total_materials,
              (SELECT COUNT(DISTINCT lm.id) FROM learning_materials lm
                 JOIN course_modules cm ON lm.module_id = cm.id
                 JOIN courses c ON cm.course_id = c.id
                 JOIN learning_progress lp ON lp.item_id = lm.id AND lp.item_type = 'material'
                   AND lp.user_id = ip.user_id AND lp.is_completed = 1
                 WHERE c.department_id = ip.department_id AND c.is_published = 1) AS completed_materials,
              (SELECT COUNT(*) FROM test_schedules ts
                 JOIN quizzes q ON ts.quiz_id = q.id
                 JOIN courses c ON q.course_id = c.id
                 LEFT JOIN quiz_attempts qa ON ts.id = qa.test_schedule_id AND qa.user_id = ip.user_id AND qa.is_passed = 1
                 WHERE c.department_id = ip.department_id AND ts.is_active = 1 AND qa.id IS NULL) AS pending_tests
       FROM intern_profiles ip
       JOIN users u ON u.id = ip.user_id
       WHERE u.role = 'intern' AND u.is_active = 1 AND u.deleted_at IS NULL`);
        let completedTraining = 0;
        let pendingTraining = 0;
        for (const row of trainingRows) {
            const totalItems = Number(row.total_videos) + Number(row.total_materials);
            const doneItems = Number(row.completed_videos) + Number(row.completed_materials);
            const isComplete = totalItems > 0 && doneItems === totalItems && Number(row.pending_tests) === 0;
            if (isComplete)
                completedTraining += 1;
            else
                pendingTraining += 1;
        }
        // Recent 10 audit logs with user info (sign-ins live on the audit log page only)
        const [recentLogs] = await pool.query(`SELECT al.*, u.name as user_name, u.role as user_role 
       FROM audit_logs al 
       LEFT JOIN users u ON al.user_id = u.id 
       WHERE al.action <> 'USER_LOGIN'
       ORDER BY al.created_at DESC LIMIT 10`);
        // Department distribution for chart
        const [deptDist] = await pool.query(`SELECT d.name, COUNT(ip.id) as intern_count 
       FROM departments d 
       LEFT JOIN intern_profiles ip ON d.id = ip.department_id 
       GROUP BY d.id, d.name`);
        // Monthly batch intake
        const [batchDist] = await pool.query(`SELECT b.name as batch_name, b.batch_code, COUNT(ip.id) as intern_count 
       FROM batches b 
       LEFT JOIN intern_profiles ip ON b.id = ip.batch_id 
       GROUP BY b.id, b.name, b.batch_code`);
        res.json({
            metrics: {
                total_interns: totalInternsRows[0]?.total || 0,
                active_interns: activeInternsRows[0]?.total || 0,
                total_team_leaders: totalTeamLeadersRows[0]?.total || 0,
                total_courses: totalCoursesRows[0]?.total || 0,
                completed_internships: completedTraining,
                pending_training: pendingTraining,
            },
            recent_activities: recentLogs,
            charts: {
                departments: deptDist,
                batches: batchDist,
            },
        });
    }
    catch (error) {
        console.error('HR Dashboard metrics error:', error);
        res.status(500).json({ error: 'Failed to fetch HR dashboard metrics' });
    }
}
// -----------------------------------------------------------------------------
// USER MANAGEMENT (Interns, Team Leaders, HR)
// -----------------------------------------------------------------------------
export async function getUsers(req, res) {
    const { role, department_id, batch_id, search, is_active } = req.query;
    try {
        let sql = `
      SELECT u.id, u.name, u.email, u.role, u.is_active, u.created_at, u.last_login_at,
             u.profile_photo_path, u.address, u.contact_number,
             ip.intern_code, ip.college_name, ip.internship_start_date, ip.internship_end_date, ip.status as intern_status,
             tl.name as assigned_team_leader_name, ip.assigned_team_leader_id,
             d.name as department_name, d.id as department_id,
             b.name as batch_name, b.batch_code, b.id as batch_id,
             tlp.employee_code, tlp.designation
      FROM users u
      LEFT JOIN intern_profiles ip ON u.id = ip.user_id
      LEFT JOIN team_leader_profiles tlp ON u.id = tlp.user_id
      LEFT JOIN departments d ON (ip.department_id = d.id OR tlp.department_id = d.id)
      LEFT JOIN batches b ON ip.batch_id = b.id
      LEFT JOIN users tl ON ip.assigned_team_leader_id = tl.id
      WHERE u.deleted_at IS NULL
    `;
        const params = [];
        if (role) {
            sql += ' AND u.role = ?';
            params.push(role);
        }
        if (department_id) {
            sql += ' AND (ip.department_id = ? OR tlp.department_id = ?)';
            params.push(department_id, department_id);
        }
        if (batch_id) {
            sql += ' AND ip.batch_id = ?';
            params.push(batch_id);
        }
        if (is_active !== undefined) {
            sql += ' AND u.is_active = ?';
            params.push(is_active === 'true' || is_active === '1' ? 1 : 0);
        }
        if (search) {
            sql += ' AND (u.name LIKE ? OR u.email LIKE ? OR ip.intern_code LIKE ?)';
            params.push(`%${search}%`, `%${search}%`, `%${search}%`);
        }
        sql += ' ORDER BY u.id DESC';
        const [rows] = await pool.query(sql, params);
        res.json({ users: rows });
    }
    catch (error) {
        console.error('HR getUsers error:', error);
        res.status(500).json({ error: 'Failed to retrieve users' });
    }
}
export async function createUser(req, res) {
    const { name, email, password, role, department_id, batch_id, assigned_team_leader_id, intern_code, employee_code, designation, college_name, internship_start_date, internship_end_date, emergency_contact, address, contact_number, profile_photo, } = req.body;
    if (!name || !email || !role) {
        res.status(400).json({ error: 'Name, email, and role are required fields' });
        return;
    }
    if (!['intern', 'team_leader', 'hr_admin'].includes(String(role))) {
        res.status(400).json({ error: 'Invalid account role' });
        return;
    }
    if ((role === 'intern' || role === 'team_leader') && !department_id) {
        res.status(400).json({ error: 'Select a department for this account.' });
        return;
    }
    if (password !== undefined && password !== null && password !== '' && !meetsPasswordPolicy(password)) {
        res.status(400).json({ error: PASSWORD_POLICY_MESSAGE });
        return;
    }
    const conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const [existing] = await conn.query('SELECT id FROM users WHERE email = ?', [email]);
        if (existing.length > 0) {
            await conn.rollback();
            res.status(400).json({ error: 'Email already registered in system' });
            return;
        }
        const initialPassword = password || DEFAULT_PASSWORD;
        const hashedPassword = await bcrypt.hash(initialPassword, 10);
        const [userResult] = await conn.query(`INSERT INTO users (name, email, password, role, is_active, address, contact_number, created_at, updated_at)
       VALUES (?, ?, ?, ?, 1, ?, ?, NOW(), NOW())`, [name, email, hashedPassword, role, address || null, contact_number || null]);
        const userId = userResult.insertId;
        if (typeof profile_photo === 'string' && profile_photo.trim().length > 0) {
            const photoPath = saveProfilePhoto(profile_photo.trim(), userId);
            await conn.query('UPDATE users SET profile_photo_path = ? WHERE id = ?', [photoPath, userId]);
        }
        if (role === 'intern') {
            const generatedCode = intern_code || `INT-${new Date().getFullYear()}-${String(userId).padStart(4, '0')}`;
            await conn.query(`INSERT INTO intern_profiles 
          (user_id, intern_code, department_id, batch_id, assigned_team_leader_id, internship_start_date, internship_end_date, status, college_name, emergency_contact, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, NOW(), NOW())`, [
                userId,
                generatedCode,
                department_id || null,
                batch_id || null,
                assigned_team_leader_id || null,
                internship_start_date || new Date().toISOString().slice(0, 10),
                internship_end_date || null,
                college_name || null,
                emergency_contact || null,
            ]);
        }
        else if (role === 'team_leader') {
            const generatedEmpCode = employee_code || `TL-${new Date().getFullYear()}-${String(userId).padStart(3, '0')}`;
            await conn.query(`INSERT INTO team_leader_profiles
          (user_id, employee_code, department_id, designation, created_at, updated_at)
         VALUES (?, ?, ?, ?, NOW(), NOW())`, [userId, generatedEmpCode, department_id || null, designation || 'Team Leader']);
        }
        await conn.commit();
        await logAuditEvent(req.user?.id || null, 'CREATE_USER', 'users', userId, null, { name, email, role }, req);
        res.status(201).json({
            message: `${role.toUpperCase()} account created successfully`,
            user_id: userId,
            default_password: initialPassword,
        });
    }
    catch (error) {
        await conn.rollback();
        if (error instanceof InvalidProfilePhotoError) {
            res.status(400).json({ error: error.message });
            return;
        }
        console.error('Create user error:', error);
        res.status(500).json({ error: 'Failed to create user account' });
    }
    finally {
        conn.release();
    }
}
export async function updateUser(req, res) {
    const { id } = req.params;
    const { name, email, department_id, batch_id, assigned_team_leader_id, internship_start_date, internship_end_date, status, designation, college_name, emergency_contact, address, contact_number, profile_photo, remove_photo, } = req.body;
    const conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const [userRows] = await conn.query('SELECT * FROM users WHERE id = ?', [id]);
        if (userRows.length === 0) {
            await conn.rollback();
            res.status(404).json({ error: 'User not found' });
            return;
        }
        const user = userRows[0];
        let photoPath = user.profile_photo_path ?? null;
        if (typeof profile_photo === 'string' && profile_photo.trim().length > 0) {
            const newPath = saveProfilePhoto(profile_photo.trim(), Number(id));
            deleteProfilePhotoFile(photoPath);
            photoPath = newPath;
        }
        else if (remove_photo === true && photoPath) {
            deleteProfilePhotoFile(photoPath);
            photoPath = null;
        }
        await conn.query('UPDATE users SET name = ?, email = ?, address = ?, contact_number = ?, profile_photo_path = ?, updated_at = NOW() WHERE id = ?', [
            name || user.name,
            email || user.email,
            address !== undefined ? (address || null) : user.address,
            contact_number !== undefined ? (contact_number || null) : user.contact_number,
            photoPath,
            id,
        ]);
        if (user.role === 'intern') {
            await conn.query(`UPDATE intern_profiles 
         SET department_id = ?, batch_id = ?, assigned_team_leader_id = ?, 
             internship_start_date = ?, internship_end_date = ?, status = COALESCE(?, status),
             college_name = ?, emergency_contact = ?, updated_at = NOW()
         WHERE user_id = ?`, [
                department_id || null,
                batch_id || null,
                assigned_team_leader_id || null,
                internship_start_date || null,
                internship_end_date || null,
                status || null,
                college_name || null,
                emergency_contact || null,
                id,
            ]);
        }
        else if (user.role === 'team_leader') {
            await conn.query(`INSERT INTO team_leader_profiles
           (user_id, employee_code, department_id, designation, created_at, updated_at)
         VALUES (?, ?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE
           department_id = VALUES(department_id),
           designation = VALUES(designation),
           updated_at = NOW()`, [
                id,
                `TL-${new Date().getFullYear()}-${String(id).padStart(3, '0')}`,
                department_id || null,
                designation || 'Team Leader',
            ]);
        }
        await conn.commit();
        await logAuditEvent(req.user?.id || null, 'UPDATE_USER', 'users', Number(id), user, req.body, req);
        res.json({ message: 'User updated successfully' });
    }
    catch (error) {
        await conn.rollback();
        if (error instanceof InvalidProfilePhotoError) {
            res.status(400).json({ error: error.message });
            return;
        }
        if (error?.code === 'ER_DUP_ENTRY') {
            res.status(409).json({ error: 'That email is already used by another account.' });
            return;
        }
        console.error('Update user error:', error);
        res.status(500).json({ error: 'Failed to update user' });
    }
    finally {
        conn.release();
    }
}
export async function toggleUserStatus(req, res) {
    const { id } = req.params;
    try {
        if (Number(id) === req.user?.id || Number(id) === 1) {
            res.status(400).json({ error: 'Cannot deactivate the primary HR Administrator account.' });
            return;
        }
        const [rows] = await pool.query('SELECT id, is_active FROM users WHERE id = ?', [id]);
        if (rows.length === 0) {
            res.status(404).json({ error: 'User not found' });
            return;
        }
        const currentStatus = rows[0].is_active;
        const newStatus = currentStatus ? 0 : 1;
        await pool.query('UPDATE users SET is_active = ?, updated_at = NOW() WHERE id = ?', [
            newStatus,
            id,
        ]);
        await logAuditEvent(req.user?.id || null, newStatus ? 'ACTIVATE_USER' : 'DEACTIVATE_USER', 'users', Number(id), { is_active: currentStatus }, { is_active: newStatus }, req);
        res.json({
            message: `User ${newStatus ? 'activated' : 'deactivated'} successfully`,
            is_active: Boolean(newStatus),
        });
    }
    catch (error) {
        console.error('Toggle status error:', error);
        res.status(500).json({ error: 'Failed to toggle user status' });
    }
}
export async function resetUserPassword(req, res) {
    const { id } = req.params;
    const { new_password } = req.body;
    if (new_password !== undefined && new_password !== null && new_password !== '' && !meetsPasswordPolicy(new_password)) {
        res.status(400).json({ error: PASSWORD_POLICY_MESSAGE });
        return;
    }
    try {
        const targetPassword = new_password || DEFAULT_PASSWORD;
        const hashed = await bcrypt.hash(targetPassword, 10);
        const [result] = await pool.query('UPDATE users SET password = ?, updated_at = NOW() WHERE id = ?', [hashed, id]);
        if (result.affectedRows === 0) {
            res.status(404).json({ error: 'User not found' });
            return;
        }
        await logAuditEvent(req.user?.id || null, 'ADMIN_RESET_PASSWORD', 'users', Number(id), null, null, req);
        res.json({
            message: 'Password reset successfully. Share the new temporary password with the user and ask them to change it after signing in.',
        });
    }
    catch (error) {
        console.error('Reset password error:', error);
        res.status(500).json({ error: 'Failed to reset password' });
    }
}
// Content authored by an account that is being removed must survive the hard
// delete, so it is reassigned to the acting HR administrator first.
async function reassignAuthoredContent(conn, fromUserId, toUserId) {
    await conn.query('UPDATE announcements SET author_id = ? WHERE author_id = ?', [toUserId, fromUserId]);
    await conn.query('UPDATE course_assignments SET assigned_by = ? WHERE assigned_by = ?', [toUserId, fromUserId]);
    await conn.query('UPDATE courses SET created_by = ? WHERE created_by = ?', [toUserId, fromUserId]);
    await conn.query('UPDATE course_module_tests SET created_by = ? WHERE created_by = ?', [toUserId, fromUserId]);
    await conn.query('UPDATE quizzes SET created_by = ? WHERE created_by = ?', [toUserId, fromUserId]);
    await conn.query('UPDATE tasks SET created_by = ? WHERE created_by = ?', [toUserId, fromUserId]);
    await conn.query('UPDATE test_schedules SET created_by = ? WHERE created_by = ?', [toUserId, fromUserId]);
}
export async function deleteUser(req, res) {
    const userId = parsePositiveInt(req.params.id);
    if (!userId) {
        res.status(400).json({ error: 'Invalid user id' });
        return;
    }
    if (userId === req.user?.id || userId === 1) {
        res.status(400).json({ error: 'Cannot delete the primary HR Administrator account.' });
        return;
    }
    const conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const [rows] = await conn.query('SELECT id, name, email, role FROM users WHERE id = ?', [userId]);
        if (rows.length === 0) {
            await conn.rollback();
            res.status(404).json({ error: 'User not found' });
            return;
        }
        const user = rows[0];
        const actingUserId = req.user?.id || 1;
        await reassignAuthoredContent(conn, userId, actingUserId);
        await conn.query('DELETE FROM users WHERE id = ?', [userId]);
        await conn.commit();
        await logAuditEvent(req.user?.id || null, 'DELETE_USER', 'users', userId, { name: user.name, email: user.email, role: user.role }, null, req);
        res.json({
            message: `${user.name}'s account and all related records were permanently deleted`,
        });
    }
    catch (error) {
        await conn.rollback();
        console.error('Delete user error:', error);
        res.status(500).json({ error: 'Failed to delete user account' });
    }
    finally {
        conn.release();
    }
}
// -----------------------------------------------------------------------------
// BATCHES & DEPARTMENTS
// -----------------------------------------------------------------------------
export async function getBatches(req, res) {
    try {
        const [rows] = await pool.query(`
      SELECT b.*, d.name as department_name, COUNT(ip.id) as intern_count
      FROM batches b
      LEFT JOIN departments d ON b.department_id = d.id
      LEFT JOIN intern_profiles ip ON b.id = ip.batch_id
      GROUP BY b.id
      ORDER BY b.id DESC
    `);
        res.json({ batches: rows });
    }
    catch (error) {
        console.error('Get batches error:', error);
        res.status(500).json({ error: 'Failed to load batches' });
    }
}
export async function createBatch(req, res) {
    const { batch_code, name, department_id, start_date, end_date } = req.body;
    const code = typeof batch_code === 'string' ? batch_code.trim() : '';
    const batchName = typeof name === 'string' ? name.trim() : '';
    if (!code || !batchName) {
        res.status(400).json({ error: 'Batch code and name are required' });
        return;
    }
    if (!department_id || !/^\d+$/.test(String(department_id))) {
        res.status(400).json({ error: 'Select a department for this batch.' });
        return;
    }
    const startDate = start_date || new Date().toISOString().slice(0, 10);
    const endDate = end_date || new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    if (endDate < startDate) {
        res.status(400).json({ error: 'End date cannot be before the start date.' });
        return;
    }
    try {
        const [resDb] = await pool.query(`INSERT INTO batches (batch_code, name, department_id, start_date, end_date, is_active, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 1, NOW(), NOW())`, [code, batchName, department_id, startDate, endDate]);
        await logAuditEvent(req.user?.id || null, 'CREATE_BATCH', 'batches', resDb.insertId, null, req.body, req);
        res.status(201).json({ message: 'Batch created successfully', batch_id: resDb.insertId });
    }
    catch (error) {
        if (error?.code === 'ER_DUP_ENTRY') {
            res.status(409).json({ error: 'A batch with this code already exists.' });
            return;
        }
        if (error?.code === 'ER_NO_REFERENCED_ROW_2') {
            res.status(400).json({ error: 'That department no longer exists.' });
            return;
        }
        console.error('Create batch error:', error);
        res.status(500).json({ error: 'Failed to create batch' });
    }
}
export async function deleteBatch(req, res) {
    const { id } = req.params;
    if (!/^\d+$/.test(id) || !Number.isSafeInteger(Number(id)) || Number(id) <= 0) {
        res.status(400).json({ error: 'Invalid batch id' });
        return;
    }
    try {
        const [rows] = await pool.query(`SELECT b.id, b.batch_code, b.name,
              (SELECT COUNT(*) FROM intern_profiles ip WHERE ip.batch_id = b.id) AS intern_count
       FROM batches b WHERE b.id = ?`, [id]);
        if (rows.length === 0) {
            res.status(404).json({ error: 'Batch not found' });
            return;
        }
        const batch = rows[0];
        await pool.query('DELETE FROM batches WHERE id = ?', [id]);
        await logAuditEvent(req.user?.id || null, 'DELETE_BATCH', 'batches', Number(id), { batch_code: batch.batch_code, name: batch.name, intern_count: Number(batch.intern_count) }, null, req);
        res.json({ message: 'Batch deleted successfully' });
    }
    catch (error) {
        if (error?.code === 'ER_ROW_IS_REFERENCED_2') {
            res.status(409).json({ error: 'Cannot delete this batch while records are still linked to it.' });
            return;
        }
        console.error('Delete batch error:', error);
        res.status(500).json({ error: 'Failed to delete batch' });
    }
}
export async function updateBatch(req, res) {
    const { id } = req.params;
    const { batch_code, name, department_id, start_date, end_date, is_active } = req.body;
    try {
        await pool.query(`UPDATE batches 
       SET batch_code = COALESCE(?, batch_code), name = COALESCE(?, name), 
           department_id = ?, start_date = ?, end_date = ?, 
           is_active = COALESCE(?, is_active), updated_at = NOW()
       WHERE id = ?`, [batch_code, name, department_id || null, start_date || null, end_date || null, is_active, id]);
        res.json({ message: 'Batch updated successfully' });
    }
    catch (error) {
        console.error('Update batch error:', error);
        res.status(500).json({ error: 'Failed to update batch' });
    }
}
export async function getDepartments(req, res) {
    try {
        const [rows] = await pool.query(`
      SELECT d.*,
             COUNT(DISTINCT intern.id) as intern_count,
             COUNT(DISTINCT leader.id) as team_leader_count,
             COUNT(DISTINCT c.id) as course_count
      FROM departments d
      LEFT JOIN intern_profiles ip ON d.id = ip.department_id
      LEFT JOIN users intern ON intern.id = ip.user_id
        AND intern.role = 'intern' AND intern.deleted_at IS NULL
      LEFT JOIN team_leader_profiles tlp ON d.id = tlp.department_id
      LEFT JOIN users leader ON leader.id = tlp.user_id
        AND leader.role = 'team_leader' AND leader.deleted_at IS NULL
      LEFT JOIN courses c ON d.id = c.department_id
      GROUP BY d.id
      ORDER BY d.name ASC
    `);
        res.json({ departments: rows });
    }
    catch (error) {
        console.error('Get departments error:', error);
        res.status(500).json({ error: 'Failed to load departments' });
    }
}
export async function createDepartment(req, res) {
    const { name, code, description } = req.body;
    if (!name || !code) {
        res.status(400).json({ error: 'Department name and code are required' });
        return;
    }
    try {
        const [resDb] = await pool.query(`INSERT INTO departments (name, code, description, is_active, created_at, updated_at)
       VALUES (?, ?, ?, 1, NOW(), NOW())`, [name, code, description || null]);
        await logAuditEvent(req.user?.id || null, 'CREATE_DEPARTMENT', 'departments', resDb.insertId, null, req.body, req);
        res.status(201).json({ message: 'Department created successfully', department_id: resDb.insertId });
    }
    catch (error) {
        console.error('Create department error:', error);
        res.status(500).json({ error: 'Failed to create department' });
    }
}
export async function deleteDepartment(req, res) {
    const { id } = req.params;
    if (!/^\d+$/.test(id) || !Number.isSafeInteger(Number(id)) || Number(id) <= 0) {
        res.status(400).json({ error: 'Invalid department id' });
        return;
    }
    try {
        const [rows] = await pool.query(`SELECT d.id, d.code, d.name,
              (SELECT COUNT(*) FROM intern_profiles ip WHERE ip.department_id = d.id) AS intern_count,
              (SELECT COUNT(*) FROM team_leader_profiles tlp WHERE tlp.department_id = d.id) AS team_leader_count,
              (SELECT COUNT(*) FROM courses c WHERE c.department_id = d.id) AS course_count,
              (SELECT COUNT(*) FROM batches b WHERE b.department_id = d.id) AS batch_count
       FROM departments d WHERE d.id = ?`, [id]);
        if (rows.length === 0) {
            res.status(404).json({ error: 'Department not found' });
            return;
        }
        const dept = rows[0];
        const blockers = [];
        if (Number(dept.intern_count) > 0)
            blockers.push(`${dept.intern_count} intern(s)`);
        if (Number(dept.team_leader_count) > 0)
            blockers.push(`${dept.team_leader_count} team leader(s)`);
        if (Number(dept.course_count) > 0)
            blockers.push(`${dept.course_count} course(s)`);
        if (Number(dept.batch_count) > 0)
            blockers.push(`${dept.batch_count} batch(es)`);
        if (blockers.length > 0) {
            res.status(409).json({
                error: `Cannot delete this department while ${blockers.join(', ')} are linked to it. Remove those links first.`,
            });
            return;
        }
        await pool.query('DELETE FROM departments WHERE id = ?', [id]);
        await logAuditEvent(req.user?.id || null, 'DELETE_DEPARTMENT', 'departments', Number(id), { code: dept.code, name: dept.name }, null, req);
        res.json({ message: 'Department deleted successfully' });
    }
    catch (error) {
        if (error?.code === 'ER_ROW_IS_REFERENCED_2') {
            res.status(409).json({ error: 'Cannot delete this department while records are still linked to it.' });
            return;
        }
        console.error('Delete department error:', error);
        res.status(500).json({ error: 'Failed to delete department' });
    }
}
export async function assignInternsToTL(req, res) {
    const { team_leader_id, intern_ids } = req.body;
    const requestedIds = Array.isArray(intern_ids)
        ? [...new Set(intern_ids.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0))]
        : [];
    if (!team_leader_id || requestedIds.length === 0) {
        res.status(400).json({ error: 'Choose a team leader and at least one intern.' });
        return;
    }
    try {
        const [leaderRows] = await pool.query(`SELECT id FROM users
        WHERE id = ? AND role = 'team_leader' AND is_active = 1 AND deleted_at IS NULL`, [Number(team_leader_id)]);
        if (leaderRows.length === 0) {
            res.status(404).json({ error: 'That team leader account is not active. Choose another team leader.' });
            return;
        }
        const placeholders = requestedIds.map(() => '?').join(',');
        const [internRows] = await pool.query(`SELECT u.id
         FROM users u
         JOIN intern_profiles ip ON ip.user_id = u.id
        WHERE u.id IN (${placeholders}) AND u.role = 'intern' AND u.is_active = 1 AND u.deleted_at IS NULL`, [...requestedIds]);
        const validIds = internRows.map((row) => Number(row.id));
        if (validIds.length === 0) {
            res.status(404).json({ error: 'None of the selected interns are active. Refresh the page and try again.' });
            return;
        }
        const updatePlaceholders = validIds.map(() => '?').join(',');
        await pool.query(`UPDATE intern_profiles 
       SET assigned_team_leader_id = ?, updated_at = NOW() 
       WHERE user_id IN (${updatePlaceholders})`, [Number(team_leader_id), ...validIds]);
        await logAuditEvent(req.user?.id || null, 'ASSIGN_INTERNS_TO_TL', 'team_leader', Number(team_leader_id), null, { intern_ids: validIds }, req);
        const skipped = requestedIds.length - validIds.length;
        res.json({
            message: skipped > 0
                ? `Assigned ${validIds.length} intern(s). ${skipped} inactive account(s) were skipped.`
                : `Assigned ${validIds.length} intern(s) to the team leader.`,
        });
    }
    catch (error) {
        console.error('Assign interns error:', error);
        res.status(500).json({ error: 'Failed to assign interns' });
    }
}
// -----------------------------------------------------------------------------
// COURSES, MODULES, VIDEOS & MATERIALS
// -----------------------------------------------------------------------------
export async function getCourses(req, res) {
    try {
        const [rows] = await pool.query(`
      SELECT c.*, d.name as department_name, u.name as creator_name,
             (SELECT COUNT(*) FROM course_modules cm WHERE cm.course_id = c.id) as module_count,
             (SELECT COUNT(*) FROM videos v JOIN course_modules cm ON v.module_id = cm.id WHERE cm.course_id = c.id) as video_count,
             (SELECT COUNT(*) FROM learning_materials lm JOIN course_modules cm ON lm.module_id = cm.id WHERE cm.course_id = c.id) as material_count,
             (SELECT COUNT(DISTINCT vwl2.user_id) FROM video_watch_logs vwl2
                JOIN videos v2 ON v2.id = vwl2.video_id
                JOIN course_modules cm2 ON cm2.id = v2.module_id
               WHERE cm2.course_id = c.id AND vwl2.last_heartbeat_at >= (NOW() - INTERVAL 30 SECOND)) as live_viewers
      FROM courses c
      LEFT JOIN departments d ON c.department_id = d.id
      LEFT JOIN users u ON c.created_by = u.id
      ORDER BY c.id DESC
    `);
        res.json({ courses: rows });
    }
    catch (error) {
        console.error('Get courses error:', error);
        res.status(500).json({ error: 'Failed to load courses' });
    }
}
export async function getCourseDetails(req, res) {
    const { id } = req.params;
    try {
        const [courseRows] = await pool.query(`SELECT c.*, d.name as department_name, u.name as creator_name 
       FROM courses c 
       LEFT JOIN departments d ON c.department_id = d.id 
       LEFT JOIN users u ON c.created_by = u.id 
       WHERE c.id = ?`, [id]);
        if (courseRows.length === 0) {
            res.status(404).json({ error: 'Course not found' });
            return;
        }
        const course = courseRows[0];
        // Fetch modules
        const [modules] = await pool.query(`SELECT * FROM course_modules WHERE course_id = ? ORDER BY order_sequence ASC`, [id]);
        // Fetch active interns of this course's department
        const [totalInternsRow] = await pool.query(`SELECT COUNT(*) as count
         FROM users u
         JOIN intern_profiles ip ON ip.user_id = u.id
        WHERE u.role = 'intern' AND u.is_active = 1 AND ip.department_id = ?`, [Number(course.department_id || 0)]);
        const totalActiveInterns = totalInternsRow[0]?.count || 0;
        // Fetch videos and materials for each module with full intern watch telemetry
        for (const mod of modules) {
            const [moduleTests] = await pool.query(`SELECT t.id, t.title, t.passing_score, COUNT(q.id) AS question_count
         FROM course_module_tests t
         LEFT JOIN course_module_test_questions q ON q.test_id = t.id
         WHERE t.module_id = ?
         GROUP BY t.id, t.title, t.passing_score
         LIMIT 1`, [mod.id]);
            mod.test = moduleTests[0] ?? null;
            const [videos] = await pool.query(`SELECT * FROM videos WHERE module_id = ? ORDER BY order_sequence ASC`, [mod.id]);
            for (const vid of videos) {
                // Query telemetry of all interns for this specific video
                const [internProgress] = await pool.query(`SELECT 
            u.id as intern_id,
            u.name as intern_name,
            u.email as intern_email,
            COALESCE(ip.intern_code, CONCAT('INT-', u.id)) as intern_code,
            COALESCE(vwl.watch_count, 0) as watch_count,
            COALESCE(vwl.total_watched_seconds, 0) as total_watched_seconds,
            COALESCE(vwl.completion_percentage, 0) as completion_percentage,
            COALESCE(vwl.is_completed, 0) as is_completed,
            vwl.last_heartbeat_at as last_watched_at
           FROM users u
           JOIN intern_profiles ip ON u.id = ip.user_id
           LEFT JOIN video_watch_logs vwl ON u.id = vwl.user_id AND vwl.video_id = ?
           WHERE u.role = 'intern' AND u.is_active = 1 AND ip.department_id = ?
           ORDER BY COALESCE(vwl.watch_count, 0) DESC, u.name ASC`, [vid.id, Number(course.department_id || 0)]);
                vid.intern_progress = internProgress;
                vid.total_views = internProgress.reduce((sum, p) => sum + Number(p.watch_count || 0), 0);
                vid.unique_viewers = internProgress.filter((p) => Number(p.watch_count || 0) > 0).length;
                vid.completed_count = internProgress.filter((p) => p.is_completed === 1 || p.is_completed === true).length;
            }
            const [materials] = await pool.query(`SELECT * FROM learning_materials WHERE module_id = ? ORDER BY order_sequence ASC`, [mod.id]);
            mod.videos = videos;
            mod.materials = materials;
        }
        course.modules = modules;
        course.total_active_interns = totalActiveInterns;
        res.json({ course });
    }
    catch (error) {
        console.error('Get course details error:', error);
        res.status(500).json({ error: 'Failed to load course details' });
    }
}
export async function createCourse(req, res) {
    const { title, description, department_id, duration_hours, is_published } = req.body;
    const courseTitle = typeof title === 'string' ? title.trim() : '';
    const departmentId = department_id == null ? null : parsePositiveInt(department_id);
    if (!courseTitle || courseTitle.length > 255) {
        res.status(400).json({ error: 'Course title is required' });
        return;
    }
    if (department_id != null && !departmentId) {
        res.status(400).json({ error: 'Invalid department id' });
        return;
    }
    const baseSlug = courseTitle.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 200) || 'course';
    try {
        const [duplicates] = await pool.query(`SELECT id, title FROM courses
       WHERE department_id <=> ? AND LOWER(TRIM(title)) = LOWER(TRIM(?))
       LIMIT 1`, [departmentId, courseTitle]);
        if (duplicates.length > 0) {
            res.status(409).json({
                error: 'A course with this title already exists in the selected department. Use the existing course and assign it to interns.',
                course_id: duplicates[0].id,
            });
            return;
        }
        let slug = baseSlug;
        let suffix = 2;
        let courseId;
        while (true) {
            try {
                const [result] = await pool.query(`INSERT INTO courses (title, slug, description, department_id, created_by, duration_hours, is_published, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`, [
                    courseTitle,
                    slug,
                    typeof description === 'string' ? description : '',
                    departmentId,
                    req.user?.id || 1,
                    parsePositiveInt(duration_hours) || 10,
                    is_published ? 1 : 0,
                ]);
                courseId = Number(result.insertId);
                break;
            }
            catch (error) {
                if (error?.code !== 'ER_DUP_ENTRY')
                    throw error;
                const [concurrentDuplicates] = await pool.query(`SELECT id FROM courses
           WHERE department_id <=> ? AND LOWER(TRIM(title)) = LOWER(TRIM(?))
           LIMIT 1`, [departmentId, courseTitle]);
                if (concurrentDuplicates.length > 0) {
                    res.status(409).json({
                        error: 'A course with this title already exists in the selected department. Use the existing course and assign it to interns.',
                        course_id: concurrentDuplicates[0].id,
                    });
                    return;
                }
                slug = `${baseSlug}-${suffix++}`;
            }
        }
        await logAuditEvent(req.user?.id || null, 'CREATE_COURSE', 'courses', courseId, null, req.body, req);
        res.status(201).json({ message: 'Course created successfully', course_id: courseId });
    }
    catch (error) {
        console.error('Create course error:', error);
        res.status(500).json({ error: 'Failed to create course' });
    }
}
export async function addModule(req, res) {
    const { course_id, title, description, order_sequence } = req.body;
    if (!course_id || !title) {
        res.status(400).json({ error: 'course_id and title are required' });
        return;
    }
    try {
        const [result] = await pool.query(`INSERT INTO course_modules (course_id, title, description, order_sequence, created_at, updated_at)
       VALUES (?, ?, ?, ?, NOW(), NOW())`, [course_id, title, description || '', order_sequence || 1]);
        res.status(201).json({ message: 'Module added successfully', module_id: result.insertId });
    }
    catch (error) {
        console.error('Add module error:', error);
        res.status(500).json({ error: 'Failed to add module' });
    }
}
export async function addVideo(req, res) {
    let { module_id, course_id, title, description, video_path, file_name, file_data, duration_seconds, min_watch_percentage, order_sequence } = req.body;
    if ((!module_id && !course_id) || !title || (!video_path && !(file_name && file_data))) {
        res.status(400).json({ error: 'module_id (or course_id), title, and a video file or video_path are required' });
        return;
    }
    let uploadedVideoPath = null;
    try {
        if (file_name && file_data) {
            const upload = decodeUpload(file_name, file_data, 'video');
            const videoUploadDir = path.resolve('uploads', 'videos');
            if (!fs.existsSync(videoUploadDir)) {
                fs.mkdirSync(videoUploadDir, { recursive: true });
            }
            const safeName = safeUploadName(String(file_name), upload.extension);
            fs.writeFileSync(path.join(videoUploadDir, safeName), upload.buffer);
            video_path = `/uploads/videos/${safeName}`;
            uploadedVideoPath = video_path;
        }
        // If course_id is provided but module_id is not, attach to existing module or create first module
        if (!module_id && course_id) {
            const [existingMods] = await pool.query(`SELECT id FROM course_modules WHERE course_id = ? ORDER BY order_sequence ASC LIMIT 1`, [course_id]);
            if (existingMods.length > 0) {
                module_id = existingMods[0].id;
            }
            else {
                const [modResult] = await pool.query(`INSERT INTO course_modules (course_id, title, description, order_sequence, created_at, updated_at)
           VALUES (?, 'Module 1: Core Curriculum & Hands-on Video Lessons', 'Foundational module for intern practical training', 1, NOW(), NOW())`, [course_id]);
                module_id = modResult.insertId;
            }
        }
        const durationSeconds = resolveStoredVideoDuration(video_path, duration_seconds);
        const [result] = await pool.query(`INSERT INTO videos (module_id, title, description, video_path, duration_seconds, min_watch_percentage, order_sequence, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`, [
            module_id,
            title,
            description || '',
            video_path,
            durationSeconds,
            min_watch_percentage || 80,
            order_sequence || 1,
        ]);
        res.status(201).json({ message: 'Video lesson added successfully', video_id: result.insertId, module_id });
    }
    catch (error) {
        if (uploadedVideoPath)
            removeStoredVideo(uploadedVideoPath);
        if (error instanceof InvalidUploadError) {
            res.status(400).json({ error: error.message });
            return;
        }
        console.error('Add video error:', error);
        res.status(500).json({ error: 'Failed to add video lesson' });
    }
}
function removeStoredVideo(videoPath) {
    if (!videoPath || !videoPath.startsWith('/uploads/'))
        return;
    try {
        const uploadsRoot = path.resolve('uploads');
        const absolute = path.resolve(videoPath.replace(/^\/+/, ''));
        if (absolute.startsWith(uploadsRoot) && fs.existsSync(absolute)) {
            fs.unlinkSync(absolute);
        }
    }
    catch {
        // A missing file never blocks removing the database record.
    }
}
// The curriculum studio is shared by HR admins and team leaders: both roles can
// already create and restructure any course here, so both may remove content
// too. The route layer already restricts these endpoints to these two roles.
async function canManageCourse(req, _courseId) {
    return req.user?.role === 'hr_admin' || req.user?.role === 'team_leader';
}
async function canManageModule(req, moduleId) {
    if (req.user?.role === 'hr_admin')
        return true;
    const [rows] = await pool.query('SELECT course_id FROM course_modules WHERE id = ?', [moduleId]);
    return rows.length > 0 && canManageCourse(req, rows[0].course_id);
}
export async function deleteVideo(req, res) {
    const { id } = req.params;
    try {
        const [rows] = await pool.query(`SELECT v.video_path, v.module_id FROM videos v WHERE v.id = ?`, [id]);
        if (rows.length === 0) {
            res.status(404).json({ error: 'Video lesson not found' });
            return;
        }
        if (!(await canManageModule(req, rows[0].module_id))) {
            res.status(403).json({ error: 'You can only delete videos in courses you created.' });
            return;
        }
        await pool.query('DELETE FROM video_watch_logs WHERE video_id = ?', [id]);
        await pool.query('DELETE FROM videos WHERE id = ?', [id]);
        removeStoredVideo(rows[0].video_path);
        await logAuditEvent(req.user?.id || null, 'DELETE_VIDEO', 'videos', Number(id), rows[0], null, req);
        res.json({ message: 'Video deleted successfully' });
    }
    catch (error) {
        console.error('Delete video error:', error);
        res.status(500).json({ error: 'Failed to delete video lesson' });
    }
}
export async function deleteCourse(req, res) {
    const { id } = req.params;
    try {
        const [existing] = await pool.query('SELECT id, title FROM courses WHERE id = ?', [id]);
        if (existing.length === 0) {
            res.status(404).json({ error: 'Course not found' });
            return;
        }
        if (!(await canManageCourse(req, id))) {
            res.status(403).json({ error: 'You can only delete courses you created.' });
            return;
        }
        // Quizzes keep their history but are removed with the course; modules, videos,
        // materials, watch logs and progress are removed by cascading constraints.
        const [videoRows] = await pool.query(`SELECT v.video_path FROM videos v
         JOIN course_modules cm ON cm.id = v.module_id
        WHERE cm.course_id = ?`, [id]);
        await pool.query('DELETE FROM quizzes WHERE course_id = ?', [id]);
        await pool.query('DELETE FROM courses WHERE id = ?', [id]);
        videoRows.forEach((v) => removeStoredVideo(v.video_path));
        await logAuditEvent(req.user?.id || null, 'DELETE_COURSE', 'courses', Number(id), existing[0], null, req);
        res.json({ message: 'Course deleted successfully' });
    }
    catch (error) {
        console.error('Delete course error:', error);
        res.status(500).json({ error: 'Failed to delete course' });
    }
}
export async function getLiveWatch(req, res) {
    try {
        const params = [];
        let teamLeaderClause = '';
        if (req.user?.role === 'team_leader') {
            teamLeaderClause = 'AND ip.assigned_team_leader_id = ?';
            params.push(req.user.id);
        }
        const [rows] = await pool.query(`SELECT vwl.id as watch_log_id,
              u.id as intern_id, u.name as intern_name, u.email as intern_email,
              COALESCE(ip.intern_code, CONCAT('INT-', u.id)) as intern_code,
              v.id as video_id, v.title as video_title, v.duration_seconds,
              cm.title as module_title,
              c.id as course_id, c.title as course_title,
              vwl.completion_percentage, vwl.last_position_seconds,
              vwl.total_watched_seconds, vwl.watch_count,
              vwl.last_heartbeat_at,
              TIMESTAMPDIFF(SECOND, vwl.last_heartbeat_at, NOW()) as seconds_ago
         FROM video_watch_logs vwl
         JOIN users u ON u.id = vwl.user_id
         LEFT JOIN intern_profiles ip ON ip.user_id = u.id
         JOIN videos v ON v.id = vwl.video_id
         JOIN course_modules cm ON cm.id = v.module_id
         JOIN courses c ON c.id = cm.course_id
        WHERE u.is_active = 1
          AND vwl.last_heartbeat_at >= (NOW() - INTERVAL 30 SECOND)
          ${teamLeaderClause}
        ORDER BY vwl.last_heartbeat_at DESC
        LIMIT 50`, params);
        res.json({
            active_viewers: rows,
            total_active: rows.length,
            server_time: new Date().toISOString(),
        });
    }
    catch (error) {
        console.error('Live watch error:', error);
        res.status(500).json({ error: 'Failed to load live watch data' });
    }
}
export async function deleteModule(req, res) {
    const { id } = req.params;
    try {
        const [moduleRows] = await pool.query('SELECT id, course_id FROM course_modules WHERE id = ?', [id]);
        if (moduleRows.length === 0) {
            res.status(404).json({ error: 'Module not found' });
            return;
        }
        if (!(await canManageCourse(req, moduleRows[0].course_id))) {
            res.status(403).json({ error: 'You can only delete modules in courses you created.' });
            return;
        }
        const [vids] = await pool.query('SELECT id, video_path FROM videos WHERE module_id = ?', [id]);
        for (const v of vids) {
            await pool.query('DELETE FROM video_watch_logs WHERE video_id = ?', [v.id]);
        }
        await pool.query('DELETE FROM videos WHERE module_id = ?', [id]);
        await pool.query('DELETE FROM learning_materials WHERE module_id = ?', [id]);
        await pool.query('DELETE FROM course_modules WHERE id = ?', [id]);
        vids.forEach((v) => removeStoredVideo(v.video_path));
        res.json({ message: 'Module deleted successfully' });
    }
    catch (error) {
        console.error('Delete module error:', error);
        res.status(500).json({ error: 'Failed to delete module' });
    }
}
// -------------------------------------------------------------
// Gen-Z Curriculum Templates Library
// -------------------------------------------------------------
export const CURRICULUM_TEMPLATES = [
    {
        id: 'it_infra',
        title: 'IT Infrastructure & Cloud Operations',
        tagline: 'Server administration, networking & production reliability',
        category: 'Infrastructure',
        icon: 'dns',
        badge: 'HOT / IN DEMAND',
        color: '#06B6D4',
        duration_hours: 14,
        description: 'Enterprise curriculum covering production server administration, deployment pipelines, secure networking, and cloud operations.',
        modules: [
            {
                title: 'Module 1: Core Systems Administration',
                description: 'Server access, automation basics, permissions, and system service management.',
                videos: [
                    {
                        title: '1.1 Systems Administration, Automation & Secure Access',
                        description: 'Managing accounts, directory structures, background services, and secure remote access practices.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                        duration_seconds: 720,
                        min_watch_percentage: 85,
                    },
                    {
                        title: '1.2 Network Fundamentals, Addressing & Traffic Flow',
                        description: 'Understanding how traffic is addressed, segmented, and routed across enterprise networks.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
                        duration_seconds: 680,
                        min_watch_percentage: 80,
                    },
                ],
            },
            {
                title: 'Module 2: Application Packaging & Delivery',
                description: 'Standardizing deployments and keeping environments consistent.',
                videos: [
                    {
                        title: '2.1 Packaging Applications for Consistent Delivery',
                        description: 'Building repeatable deployment units, managing versions, and testing release candidates.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
                        duration_seconds: 820,
                        min_watch_percentage: 85,
                    },
                    {
                        title: '2.2 Multi-Service Environments & Data Persistence',
                        description: 'Running connected services together, isolated networks, and durable storage practices.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
                        duration_seconds: 750,
                        min_watch_percentage: 80,
                    },
                ],
            },
            {
                title: 'Module 3: Cloud Networking & Traffic Management',
                description: 'Production network topology, secure connections, and traffic distribution.',
                videos: [
                    {
                        title: '3.1 Private Networks, Access Policies & Routing',
                        description: 'Designing private and public segments, access control rules, and resilient routing.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
                        duration_seconds: 900,
                        min_watch_percentage: 90,
                    },
                    {
                        title: '3.2 Secure Traffic Front-Doors & Certificate Management',
                        description: 'Encrypted connections, request distribution, health checks, and failover handling.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4',
                        duration_seconds: 650,
                        min_watch_percentage: 80,
                    },
                ],
            },
        ],
    },
    {
        id: 'fullstack_web',
        title: 'Full-Stack Application Engineering',
        tagline: 'Service APIs, interactive interfaces & data modelling',
        category: 'Software Engineering',
        icon: 'code',
        badge: 'CORE TRACK',
        color: '#6366F1',
        duration_hours: 16,
        description: 'End-to-end application development from clean service architecture to modern, responsive interface design.',
        modules: [
            {
                title: 'Module 1: Service Engineering & Access Control',
                description: 'Clean architectural layers, request validation, authentication, and transactional data handling.',
                videos: [
                    {
                        title: '1.1 Structuring Services, Controllers & Validation',
                        description: 'Separation of concerns, request validation, and structured error handling.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                        duration_seconds: 700,
                        min_watch_percentage: 85,
                    },
                    {
                        title: '1.2 Session Tokens, Password Safety & Role Guards',
                        description: 'Secure sessions, password storage practices, and permission policies.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
                        duration_seconds: 640,
                        min_watch_percentage: 80,
                    },
                ],
            },
            {
                title: 'Module 2: Interactive Interface Design',
                description: 'Modern component composition, reusable patterns, and state architecture.',
                videos: [
                    {
                        title: '2.1 Component Architecture, Lifecycle & State Design',
                        description: 'Managing updates, performance, and modular shared state across screens.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
                        duration_seconds: 800,
                        min_watch_percentage: 85,
                    },
                ],
            },
        ],
    },
    {
        id: 'cybersecurity',
        title: 'Cybersecurity & Threat Defense',
        tagline: 'Network hardening, secure coding, monitoring & incident response',
        category: 'Security',
        icon: 'security',
        badge: 'SECURITY ESSENTIALS',
        color: '#EF4444',
        duration_hours: 12,
        description: 'Security fundamentals, zero trust principles, defensive testing basics, and security log monitoring.',
        modules: [
            {
                title: 'Module 1: Application Security Essentials',
                description: 'Identifying and preventing injection, script injection, request forgery, and broken access controls.',
                videos: [
                    {
                        title: '1.1 Defending Against Injection & Script Exploits',
                        description: 'Safe queries, input sanitization, content policies, and secure session storage.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                        duration_seconds: 750,
                        min_watch_percentage: 90,
                    },
                ],
            },
            {
                title: 'Module 2: Network Hardening & Security Monitoring',
                description: 'Traffic analysis, audit trails, and continuous monitoring practices.',
                videos: [
                    {
                        title: '2.1 Audit Trail Analysis & Intrusion Detection',
                        description: 'Reviewing security events, spotting anomalous activity, and automated incident triage.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
                        duration_seconds: 720,
                        min_watch_percentage: 85,
                    },
                ],
            },
        ],
    },
    {
        id: 'qa_testing',
        title: 'Quality Assurance & Test Engineering',
        tagline: 'Systematic testing, regression coverage & release confidence',
        category: 'Quality Assurance',
        icon: 'fact_check',
        badge: 'TESTING & RELIABILITY',
        color: '#10B981',
        duration_hours: 10,
        description: 'Comprehensive test engineering including automated regression suites, mocking, and release integration.',
        modules: [
            {
                title: 'Module 1: Unit & Integration Test Engineering',
                description: 'Test-driven development, assertions, and reusable test fixtures.',
                videos: [
                    {
                        title: '1.1 Writing Reliable Unit Tests & Mocking Dependencies',
                        description: 'Isolating tests, simulating external services, and measuring coverage.',
                        video_path: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                        duration_seconds: 680,
                        min_watch_percentage: 85,
                    },
                ],
            },
        ],
    },
];
export async function getCourseTemplates(req, res) {
    res.json({ templates: CURRICULUM_TEMPLATES });
}
export async function applyCourseTemplate(req, res) {
    const { id } = req.params;
    const { template_id } = req.body;
    const template = CURRICULUM_TEMPLATES.find(t => t.id === template_id);
    if (!template) {
        res.status(404).json({ error: 'Curriculum template not found' });
        return;
    }
    try {
        for (let mIdx = 0; mIdx < template.modules.length; mIdx++) {
            const mod = template.modules[mIdx];
            const [modRes] = await pool.query(`INSERT INTO course_modules (course_id, title, description, order_sequence, created_at, updated_at)
         VALUES (?, ?, ?, ?, NOW(), NOW())`, [id, mod.title, mod.description || '', mIdx + 1]);
            const moduleId = modRes.insertId;
            for (let vIdx = 0; vIdx < mod.videos.length; vIdx++) {
                const vid = mod.videos[vIdx];
                await pool.query(`INSERT INTO videos (module_id, title, description, video_path, duration_seconds, min_watch_percentage, order_sequence, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`, [
                    moduleId,
                    vid.title,
                    vid.description || '',
                    vid.video_path,
                    vid.duration_seconds || 600,
                    vid.min_watch_percentage || 80,
                    vIdx + 1,
                ]);
            }
        }
        res.status(201).json({
            message: `Template "${template.title}" applied successfully with ${template.modules.length} modules!`,
            modules_count: template.modules.length
        });
    }
    catch (error) {
        console.error('Apply template error:', error);
        res.status(500).json({ error: 'Failed to apply curriculum template' });
    }
}
export async function addMaterial(req, res) {
    const { module_id, title, material_type, file_path, file_size_kb, allow_download, order_sequence } = req.body;
    if (!module_id || !title || !file_path) {
        res.status(400).json({ error: 'module_id, title, and file_path are required' });
        return;
    }
    try {
        const [result] = await pool.query(`INSERT INTO learning_materials (module_id, title, material_type, file_path, file_size_kb, allow_download, order_sequence, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`, [
            module_id,
            title,
            material_type || 'sop',
            file_path,
            file_size_kb || 512,
            allow_download !== undefined ? (allow_download ? 1 : 0) : 1,
            order_sequence || 1,
        ]);
        res.status(201).json({ message: 'Learning material added successfully', material_id: result.insertId });
    }
    catch (error) {
        console.error('Add material error:', error);
        res.status(500).json({ error: 'Failed to add learning material' });
    }
}
// -----------------------------------------------------------------------------
// ANNOUNCEMENTS
// -----------------------------------------------------------------------------
export async function getAnnouncements(req, res) {
    try {
        const [rows] = await pool.query(`
      SELECT a.*, u.name as author_name, b.name as batch_name, d.name as department_name
      FROM announcements a
      LEFT JOIN users u ON a.author_id = u.id
      LEFT JOIN batches b ON a.target_batch_id = b.id
      LEFT JOIN departments d ON a.target_department_id = d.id
      ORDER BY a.priority = 'urgent' DESC, a.created_at DESC
    `);
        res.json({ announcements: rows });
    }
    catch (error) {
        console.error('Get announcements error:', error);
        res.status(500).json({ error: 'Failed to load announcements' });
    }
}
export async function createAnnouncement(req, res) {
    const { title, content, priority, target_batch_id, target_department_id, is_global, expires_at } = req.body;
    if (!title || !content) {
        res.status(400).json({ error: 'Title and content are required' });
        return;
    }
    try {
        const [result] = await pool.query(`INSERT INTO announcements (author_id, title, content, priority, target_batch_id, target_department_id, is_global, expires_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`, [
            req.user?.id || 1,
            title,
            content,
            priority || 'normal',
            target_batch_id || null,
            target_department_id || null,
            is_global ? 1 : 0,
            expires_at || null,
        ]);
        await fanOutAnnouncementNotifications(result.insertId, req.user?.id || 1, title, content, Boolean(is_global), target_batch_id || null, target_department_id || null);
        await logAuditEvent(req.user?.id || null, 'CREATE_ANNOUNCEMENT', 'announcements', result.insertId, null, req.body, req);
        res.status(201).json({ message: 'Announcement published successfully', announcement_id: result.insertId });
    }
    catch (error) {
        console.error('Create announcement error:', error);
        res.status(500).json({ error: 'Failed to create announcement' });
    }
}
export async function deleteAnnouncement(req, res) {
    const { id } = req.params;
    try {
        await pool.query('DELETE FROM announcements WHERE id = ?', [id]);
        res.json({ message: 'Announcement deleted successfully' });
    }
    catch (error) {
        console.error('Delete announcement error:', error);
        res.status(500).json({ error: 'Failed to delete announcement' });
    }
}
// -----------------------------------------------------------------------------
// PERFORMANCE REPORTS & EXPORTS
// -----------------------------------------------------------------------------
export async function getReports(req, res) {
    try {
        const [rows] = await pool.query(`
      SELECT u.id as user_id, u.name, u.email, ip.intern_code,
             d.name as department_name, b.name as batch_name, tl.name as team_leader_name,
             COALESCE(w.total_watched_seconds, 0) as total_watched_seconds,
             COALESCE(w.videos_completed, 0) as videos_completed,
             COALESCE(q.tests_attempted, 0) as tests_attempted,
             COALESCE(q.tests_passed, 0) as tests_passed,
             COALESCE(q.avg_test_score, 0) as avg_test_score,
             COALESCE(t.tasks_submitted, 0) as tasks_submitted
      FROM users u
      JOIN intern_profiles ip ON u.id = ip.user_id
      LEFT JOIN departments d ON ip.department_id = d.id
      LEFT JOIN batches b ON ip.batch_id = b.id
      LEFT JOIN users tl ON ip.assigned_team_leader_id = tl.id
      LEFT JOIN (
        SELECT user_id,
               ROUND(SUM(total_watched_seconds)) as total_watched_seconds,
               SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) as videos_completed
        FROM video_watch_logs
        GROUP BY user_id
      ) w ON u.id = w.user_id
      LEFT JOIN (
        SELECT qa.user_id,
               COUNT(*) as tests_attempted,
               SUM(CASE WHEN qa.is_passed = 1 AND qa.needs_review = 0 THEN 1 ELSE 0 END) as tests_passed,
               ROUND(AVG(CASE WHEN qa.needs_review = 0
                              THEN qa.total_score / NULLIF(qz.total_marks, 0) * 100 END), 1) as avg_test_score
        FROM quiz_attempts qa
        JOIN quizzes qz ON qa.quiz_id = qz.id
        WHERE qa.status = 'submitted'
        GROUP BY qa.user_id
      ) q ON u.id = q.user_id
      LEFT JOIN (
        SELECT user_id, COUNT(*) as tasks_submitted
        FROM task_submissions
        GROUP BY user_id
      ) t ON u.id = t.user_id
      WHERE u.deleted_at IS NULL AND u.role = 'intern'
      ORDER BY u.name ASC
    `);
        res.json({ reports: rows });
    }
    catch (error) {
        console.error('Get reports error:', error);
        res.status(500).json({ error: 'Failed to generate performance reports' });
    }
}
export async function getFeedback(req, res) {
    try {
        const [rows] = await pool.query(`
      SELECT f.id, f.rating, f.comments, f.context_type, f.created_at,
             intern.id AS intern_id, intern.name AS intern_name,
             ip.intern_code, d.name AS department_name,
             leader.name AS team_leader_name,
             'feedback' AS source, NULL AS task_title,
             NULL AS score, NULL AS max_score, NULL AS submission_status
      FROM feedback f
      JOIN users intern ON intern.id = f.to_user_id
        AND intern.role = 'intern' AND intern.deleted_at IS NULL
      LEFT JOIN intern_profiles ip ON ip.user_id = intern.id
      LEFT JOIN departments d ON ip.department_id = d.id
      LEFT JOIN users leader ON leader.id = f.from_user_id
      WHERE f.context_type <> 'question'
      UNION ALL
      SELECT ts.id, NULL AS rating, ts.tl_feedback AS comments,
             'task' AS context_type, COALESCE(ts.graded_at, ts.updated_at) AS created_at,
             intern.id AS intern_id, intern.name AS intern_name,
             ip.intern_code, d.name AS department_name,
             leader.name AS team_leader_name,
             'task_submission' AS source, t.title AS task_title,
             ts.score, t.max_score, ts.status AS submission_status
      FROM task_submissions ts
      JOIN tasks t ON t.id = ts.task_id
      JOIN users intern ON intern.id = ts.user_id
        AND intern.role = 'intern' AND intern.deleted_at IS NULL
      LEFT JOIN intern_profiles ip ON ip.user_id = intern.id
      LEFT JOIN departments d ON ip.department_id = d.id
      LEFT JOIN users leader ON leader.id = ts.graded_by
      WHERE ts.status IN ('graded', 'resubmission_required')
        AND (ts.score IS NOT NULL OR NULLIF(TRIM(ts.tl_feedback), '') IS NOT NULL)
      ORDER BY created_at DESC, id DESC, source ASC
    `);
        res.json({ feedback: rows });
    }
    catch (error) {
        console.error('Get feedback error:', error);
        res.status(500).json({ error: 'Failed to load feedback' });
    }
}
export async function updateInternName(req, res) {
    const { id } = req.params;
    if (!/^\d+$/.test(id) || !Number.isSafeInteger(Number(id)) || Number(id) <= 0) {
        res.status(400).json({ error: 'Invalid intern id' });
        return;
    }
    const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
    if (name.length < 2 || name.length > 100) {
        res.status(400).json({ error: 'Enter a name between 2 and 100 characters.' });
        return;
    }
    try {
        const [rows] = await pool.query(`SELECT id, name FROM users WHERE id = ? AND role = 'intern' AND deleted_at IS NULL`, [id]);
        if (rows.length === 0) {
            res.status(404).json({ error: 'Intern not found' });
            return;
        }
        const previousName = rows[0].name;
        await pool.query('UPDATE users SET name = ?, updated_at = NOW() WHERE id = ?', [name, id]);
        await logAuditEvent(req.user?.id || null, 'UPDATE_INTERN_NAME', 'users', Number(id), { name: previousName }, { name }, req);
        res.json({ message: 'Intern name updated successfully', name });
    }
    catch (error) {
        console.error('Update intern name error:', error);
        res.status(500).json({ error: 'Failed to update intern name' });
    }
}
export async function exportReportsCsv(req, res) {
    try {
        const [rows] = await pool.query(`
      SELECT u.name, u.email, ip.intern_code, d.name as department, b.name as batch, tl.name as team_leader,
             ROUND(COALESCE(w.total_watched_seconds, 0) / 60, 1) as watched_minutes,
             COALESCE(w.videos_completed, 0) as videos_completed,
             COALESCE(q.tests_passed, 0) as tests_passed,
             COALESCE(q.tests_attempted, 0) as tests_attempted,
             COALESCE(q.avg_quiz_score, 0) as avg_quiz_score,
             COALESCE(t.tasks_submitted, 0) as tasks_submitted
      FROM users u
      JOIN intern_profiles ip ON u.id = ip.user_id
      LEFT JOIN departments d ON ip.department_id = d.id
      LEFT JOIN batches b ON ip.batch_id = b.id
      LEFT JOIN users tl ON ip.assigned_team_leader_id = tl.id
      LEFT JOIN (
        SELECT user_id, SUM(total_watched_seconds) as total_watched_seconds,
               SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) as videos_completed
        FROM video_watch_logs
        GROUP BY user_id
      ) w ON u.id = w.user_id
      LEFT JOIN (
        SELECT qa.user_id,
               COUNT(*) as tests_attempted,
               SUM(CASE WHEN qa.is_passed = 1 AND qa.needs_review = 0 THEN 1 ELSE 0 END) as tests_passed,
               ROUND(AVG(CASE WHEN qa.needs_review = 0
                              THEN qa.total_score / NULLIF(qz.total_marks, 0) * 100 END), 1) as avg_quiz_score
        FROM quiz_attempts qa
        JOIN quizzes qz ON qa.quiz_id = qz.id
        WHERE qa.status = 'submitted'
        GROUP BY qa.user_id
      ) q ON u.id = q.user_id
      LEFT JOIN (
        SELECT user_id, COUNT(*) as tasks_submitted
        FROM task_submissions
        GROUP BY user_id
      ) t ON u.id = t.user_id
      WHERE u.deleted_at IS NULL AND u.role = 'intern'
      ORDER BY u.name ASC
    `);
        let csv = 'Name,Email,Intern Code,Department,Batch,Team Leader,Watched Minutes,Videos Completed,Tests Passed,Tests Taken,Avg Quiz Score (%),Tasks Submitted\n';
        for (const r of rows) {
            csv += `"${r.name}","${r.email}","${r.intern_code}","${r.department || ''}","${r.batch || ''}","${r.team_leader || ''}",${r.watched_minutes || 0},${r.videos_completed || 0},${r.tests_passed || 0},${r.tests_attempted || 0},${r.avg_quiz_score || 0},${r.tasks_submitted || 0}\n`;
        }
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', 'attachment; filename="kgpl_intern_performance_report.csv"');
        res.send(csv);
    }
    catch (error) {
        console.error('Export CSV error:', error);
        res.status(500).json({ error: 'Failed to export CSV report' });
    }
}
// -----------------------------------------------------------------------------
// AUDIT LOGS
// -----------------------------------------------------------------------------
export async function getAuditLogs(req, res) {
    const { page = 1, limit = 50 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);
    try {
        const [rows] = await pool.query(`SELECT al.*, u.name as user_name, u.email as user_email, u.role as user_role
       FROM audit_logs al
       LEFT JOIN users u ON al.user_id = u.id
       ORDER BY al.id DESC
       LIMIT ? OFFSET ?`, [Number(limit), Number(offset)]);
        const [countRows] = await pool.query('SELECT COUNT(*) as total FROM audit_logs');
        res.json({
            audit_logs: rows,
            total: countRows[0].total,
            page: Number(page),
            limit: Number(limit),
        });
    }
    catch (error) {
        console.error('Get audit logs error:', error);
        res.status(500).json({ error: 'Failed to load audit logs' });
    }
}
// -----------------------------------------------------------------------------
// CERTIFICATE EDITING
// -----------------------------------------------------------------------------
function parseCertificateDate(value) {
    if (value === undefined || value === null || value === '')
        return null;
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value))
        return undefined;
    const parsed = new Date(`${value}T00:00:00Z`);
    if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value)
        return undefined;
    return value;
}
function optionalCertificateText(value, max) {
    if (value === undefined || value === null)
        return null;
    if (typeof value !== 'string')
        return undefined;
    const trimmed = value.trim();
    if (trimmed === '')
        return null;
    return trimmed.length <= max ? trimmed : undefined;
}
export async function listCertificates(req, res) {
    try {
        const [rows] = await pool.query(`SELECT u.id AS intern_user_id, u.name AS intern_name, u.email,
              ip.id AS intern_profile_id, ip.intern_code, ip.status,
              d.name AS department,
              c.id AS override_id, c.recipient_name, c.intern_code AS override_intern_code,
              c.department AS override_department, c.body_text, c.signer_name, c.signer_title,
              c.organization, DATE_FORMAT(c.issue_date, '%Y-%m-%d') AS issue_date, c.serial,
              c.updated_at AS override_updated_at
       FROM users u
       JOIN intern_profiles ip ON ip.user_id = u.id
       LEFT JOIN departments d ON ip.department_id = d.id
       LEFT JOIN certificates c ON c.intern_user_id = u.id
       WHERE u.role = 'intern' AND u.deleted_at IS NULL
       ORDER BY u.name ASC`);
        const certificates = rows.map((row) => {
            const defaults = buildDefaultCertificate({
                recipientName: row.intern_name,
                internCode: row.intern_code,
                department: row.department || '',
                serial: defaultSerial(Number(row.intern_profile_id)),
            });
            const override = row.override_id
                ? {
                    recipient_name: row.recipient_name,
                    intern_code: row.override_intern_code,
                    department: row.override_department,
                    body_text: row.body_text,
                    signer_name: row.signer_name,
                    signer_title: row.signer_title,
                    organization: row.organization,
                    issue_date: row.issue_date,
                    serial: row.serial,
                }
                : null;
            return {
                intern_user_id: row.intern_user_id,
                intern_name: row.intern_name,
                email: row.email,
                status: row.status,
                has_custom: Boolean(row.override_id),
                updated_at: row.override_updated_at,
                defaults,
                certificate: mergeCertificate(defaults, override),
            };
        });
        res.json({ certificates });
    }
    catch (error) {
        console.error('List certificates error:', error);
        res.status(500).json({ error: 'Failed to load certificates' });
    }
}
export async function updateCertificate(req, res) {
    const { internId } = req.params;
    if (!/^\d+$/.test(internId) || !Number.isSafeInteger(Number(internId)) || Number(internId) <= 0) {
        res.status(400).json({ error: 'Invalid intern id' });
        return;
    }
    const body = req.body || {};
    const recipientName = typeof body.recipient_name === 'string' ? body.recipient_name.trim() : '';
    if (recipientName.length < 2 || recipientName.length > 100) {
        res.status(400).json({ error: 'Recipient name must be between 2 and 100 characters.' });
        return;
    }
    const signerName = typeof body.signer_name === 'string' ? body.signer_name.trim() : '';
    if (signerName.length < 2 || signerName.length > 100) {
        res.status(400).json({ error: 'Signer name must be between 2 and 100 characters.' });
        return;
    }
    const bodyText = typeof body.body_text === 'string' ? body.body_text.trim() : '';
    if (bodyText.length < 10 || bodyText.length > 1000) {
        res.status(400).json({ error: 'Certificate body must be between 10 and 1000 characters.' });
        return;
    }
    const internCode = optionalCertificateText(body.intern_code, 50);
    const department = optionalCertificateText(body.department, 100);
    const signerTitle = optionalCertificateText(body.signer_title, 150);
    const organization = optionalCertificateText(body.organization, 150);
    const serial = optionalCertificateText(body.serial, 100);
    const issueDate = parseCertificateDate(body.issue_date);
    if (internCode === undefined) {
        res.status(400).json({ error: 'Intern ID must be at most 50 characters.' });
        return;
    }
    if (department === undefined) {
        res.status(400).json({ error: 'Department must be at most 100 characters.' });
        return;
    }
    if (signerTitle === undefined) {
        res.status(400).json({ error: 'Signer title must be at most 150 characters.' });
        return;
    }
    if (organization === undefined) {
        res.status(400).json({ error: 'Organization must be at most 150 characters.' });
        return;
    }
    if (serial === undefined) {
        res.status(400).json({ error: 'Certificate serial must be at most 100 characters.' });
        return;
    }
    if (issueDate === undefined) {
        res.status(400).json({ error: 'Issue date must be a valid date in YYYY-MM-DD format.' });
        return;
    }
    try {
        const [internRows] = await pool.query(`SELECT u.id, u.name, ip.id AS intern_profile_id, ip.intern_code, d.name AS department
       FROM users u
       JOIN intern_profiles ip ON ip.user_id = u.id
       LEFT JOIN departments d ON ip.department_id = d.id
       WHERE u.id = ? AND u.role = 'intern' AND u.deleted_at IS NULL`, [internId]);
        if (internRows.length === 0) {
            res.status(404).json({ error: 'Intern not found' });
            return;
        }
        const intern = internRows[0];
        const [previousRows] = await pool.query('SELECT * FROM certificates WHERE intern_user_id = ?', [internId]);
        const previous = previousRows[0] || null;
        await pool.query(`INSERT INTO certificates
         (intern_user_id, recipient_name, intern_code, department, body_text,
          signer_name, signer_title, organization, issue_date, serial, updated_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         recipient_name = VALUES(recipient_name),
         intern_code = VALUES(intern_code),
         department = VALUES(department),
         body_text = VALUES(body_text),
         signer_name = VALUES(signer_name),
         signer_title = VALUES(signer_title),
         organization = VALUES(organization),
         issue_date = VALUES(issue_date),
         serial = VALUES(serial),
         updated_by = VALUES(updated_by),
         updated_at = NOW()`, [
            internId,
            recipientName,
            internCode,
            department,
            bodyText,
            signerName,
            signerTitle,
            organization,
            issueDate,
            serial,
            req.user?.id || null,
        ]);
        await logAuditEvent(req.user?.id || null, 'UPDATE_CERTIFICATE', 'certificates', Number(internId), previous, {
            recipient_name: recipientName,
            intern_code: internCode,
            department,
            body_text: bodyText,
            signer_name: signerName,
            signer_title: signerTitle,
            organization,
            issue_date: issueDate,
            serial,
        }, req);
        const defaults = buildDefaultCertificate({
            recipientName: intern.name,
            internCode: intern.intern_code,
            department: intern.department || '',
            serial: defaultSerial(Number(intern.intern_profile_id)),
        });
        const certificate = mergeCertificate(defaults, {
            recipient_name: recipientName,
            intern_code: internCode,
            department,
            body_text: bodyText,
            signer_name: signerName,
            signer_title: signerTitle,
            organization,
            issue_date: issueDate,
            serial,
        });
        res.json({ message: 'Certificate updated successfully', certificate });
    }
    catch (error) {
        console.error('Update certificate error:', error);
        res.status(500).json({ error: 'Failed to update certificate' });
    }
}
export async function resetCertificate(req, res) {
    const { internId } = req.params;
    if (!/^\d+$/.test(internId) || !Number.isSafeInteger(Number(internId)) || Number(internId) <= 0) {
        res.status(400).json({ error: 'Invalid intern id' });
        return;
    }
    try {
        const [internRows] = await pool.query(`SELECT u.id, u.name, ip.id AS intern_profile_id, ip.intern_code, d.name AS department
       FROM users u
       JOIN intern_profiles ip ON ip.user_id = u.id
       LEFT JOIN departments d ON ip.department_id = d.id
       WHERE u.id = ? AND u.role = 'intern' AND u.deleted_at IS NULL`, [internId]);
        if (internRows.length === 0) {
            res.status(404).json({ error: 'Intern not found' });
            return;
        }
        const [previousRows] = await pool.query('SELECT * FROM certificates WHERE intern_user_id = ?', [internId]);
        await pool.query('DELETE FROM certificates WHERE intern_user_id = ?', [internId]);
        await logAuditEvent(req.user?.id || null, 'RESET_CERTIFICATE', 'certificates', Number(internId), previousRows[0] || null, null, req);
        const intern = internRows[0];
        const certificate = buildDefaultCertificate({
            recipientName: intern.name,
            internCode: intern.intern_code,
            department: intern.department || '',
            serial: defaultSerial(Number(intern.intern_profile_id)),
        });
        res.json({ message: 'Certificate reset to defaults', certificate });
    }
    catch (error) {
        console.error('Reset certificate error:', error);
        res.status(500).json({ error: 'Failed to reset certificate' });
    }
}
export async function getNoSqlUsageStats(req, res) {
    try {
        const telemetryCol = getMongoCollection('video_telemetry');
        const usageCol = getMongoCollection('video_usage');
        const recentHeartbeats = await telemetryCol.find({});
        const usageList = await usageCol.find({});
        const heartbeats = await recentHeartbeats.toArray();
        const usage = await usageList.toArray();
        res.json({
            status: 'active',
            engine: 'MongoDB NoSQL Usage Engine',
            total_heartbeats_ingested: heartbeats.length,
            tracked_video_sessions: usage.length,
            recent_heartbeats: heartbeats.slice(-20).reverse(),
            usage_summary: usage,
        });
    }
    catch (error) {
        console.error('Get NoSQL usage stats error:', error);
        res.status(500).json({ error: 'Failed to load NoSQL telemetry usage' });
    }
}
