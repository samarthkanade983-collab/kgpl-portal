import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { pool } from '../config/db.js';
import { JWT_SECRET } from '../middleware/auth.js';
import { logAuditEvent } from '../middleware/audit.js';
import { recordFailedLogin, clearFailedLogins } from '../middleware/rateLimit.js';
// Static placeholder hash checked for unknown accounts to keep login timing uniform.
const DUMMY_PASSWORD_HASH = '$2a$10$ahH/Y3S0IHf17U5/mCPJ3.XhuI3EqYBinj.aXu7/2.tJGkEVfVfCi';
export async function login(req, res) {
    const { email, password } = req.body;
    if (!email || !password) {
        res.status(400).json({ error: 'Email and password are required' });
        return;
    }
    try {
        // Map alias emails so both intern1@kgpl.com and intern@kgpl.com work seamlessly
        let lookupEmail = email.trim().toLowerCase();
        if (lookupEmail === 'intern1@kgpl.com') {
            lookupEmail = 'intern@kgpl.com';
        }
        let [rows] = await pool.query(`SELECT id, name, email, password, role, is_active, profile_photo_path, address, contact_number
       FROM users WHERE (email = ? OR email = ?) AND deleted_at IS NULL`, [lookupEmail, email.trim()]);
        if (rows.length === 0) {
            // Equalize response time so unknown emails cannot be distinguished from
            // wrong passwords by timing.
            try {
                await bcrypt.compare(password, DUMMY_PASSWORD_HASH);
            }
            catch (_) { }
            recordFailedLogin(req);
            res.status(401).json({ error: 'Invalid email or password credentials' });
            return;
        }
        const user = rows[0];
        let isMatch = false;
        try {
            isMatch = await bcrypt.compare(password, user.password);
        }
        catch (_) {
            isMatch = false;
        }
        if (!isMatch) {
            recordFailedLogin(req);
            res.status(401).json({ error: 'Invalid email or password credentials' });
            return;
        }
        if (!user.is_active) {
            res.status(403).json({ error: 'Account has been deactivated. Please contact HR.' });
            return;
        }
        clearFailedLogins(req);
        // Generate JWT token valid for 24h
        const token = jwt.sign({ id: user.id, role: user.role, email: user.email }, JWT_SECRET, { expiresIn: '24h', algorithm: 'HS256' });
        // Update login timestamp
        const clientIp = req.ip || '127.0.0.1';
        await pool.query('UPDATE users SET last_login_at = NOW(), last_login_ip = ? WHERE id = ?', [
            clientIp,
            user.id,
        ]);
        await logAuditEvent(user.id, 'USER_LOGIN', 'users', user.id, null, { ip: clientIp }, req);
        res.json({
            token,
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                role: user.role,
                is_active: Boolean(user.is_active),
                profile_photo_path: user.profile_photo_path ?? null,
                address: user.address ?? null,
                contact_number: user.contact_number ?? null,
            },
        });
    }
    catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ error: 'Internal server authentication error' });
    }
}
export async function me(req, res) {
    const user = req.user;
    try {
        let profileData = null;
        if (user.role === 'intern') {
            const [profiles] = await pool.query(`SELECT ip.*, d.name AS department_name, b.batch_code, b.name AS batch_name, u.name AS team_leader_name
         FROM intern_profiles ip
         LEFT JOIN departments d ON ip.department_id = d.id
         LEFT JOIN batches b ON ip.batch_id = b.id
         LEFT JOIN users u ON ip.assigned_team_leader_id = u.id
         WHERE ip.user_id = ?`, [user.id]);
            profileData = profiles[0] || null;
        }
        else if (user.role === 'team_leader') {
            const [profiles] = await pool.query(`SELECT tlp.*, d.name AS department_name
         FROM team_leader_profiles tlp
         LEFT JOIN departments d ON tlp.department_id = d.id
         WHERE tlp.user_id = ?`, [user.id]);
            profileData = profiles[0] || null;
        }
        const [unreadRows] = await pool.query('SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0', [user.id]);
        res.json({
            user,
            profile: profileData,
            unread_notifications_count: unreadRows[0]?.count || 0,
        });
    }
    catch (error) {
        console.error('Me query error:', error);
        res.status(500).json({ error: 'Failed to retrieve user profile' });
    }
}
export async function getPublicDepartments(req, res) {
    try {
        const [rows] = await pool.query('SELECT id, name FROM departments ORDER BY name ASC');
        res.json({ departments: rows });
    }
    catch (error) {
        console.error('Public departments error:', error);
        res.status(500).json({ error: 'Failed to retrieve departments' });
    }
}
export async function register(req, res) {
    const { name, email, password, department_id } = req.body;
    if (!name || !email || !password) {
        res.status(400).json({ error: 'Full name, email address, and password are required' });
        return;
    }
    if (password.length < 8 || !/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
        res.status(400).json({ error: 'Password must be at least 8 characters and contain both letters and numbers' });
        return;
    }
    const departmentId = Number(department_id);
    if (!Number.isInteger(departmentId) || departmentId <= 0) {
        res.status(400).json({ error: 'Please select a department' });
        return;
    }
    // Self-registration always creates an intern account. Team Leader accounts
    // are provisioned by HR so a public visitor cannot grant themselves access.
    const cleanRole = 'intern';
    const emailLower = email.trim().toLowerCase();
    const connection = await pool.getConnection();
    try {
        await connection.beginTransaction();
        const [existing] = await connection.query('SELECT id FROM users WHERE email = ?', [emailLower]);
        if (existing.length > 0) {
            await connection.rollback();
            res.status(409).json({ error: 'An account with this email address already exists' });
            return;
        }
        const [deptRows] = await connection.query('SELECT id FROM departments WHERE id = ?', [departmentId]);
        if (deptRows.length === 0) {
            await connection.rollback();
            res.status(400).json({ error: 'Please select a valid department' });
            return;
        }
        const hashedPassword = await bcrypt.hash(password, 10);
        const [userResult] = await connection.query(`INSERT INTO users (name, email, password, role, is_active, created_at, updated_at)
       VALUES (?, ?, ?, ?, 1, NOW(), NOW())`, [name.trim(), emailLower, hashedPassword, cleanRole]);
        const newUserId = userResult.insertId;
        const code = `KGPL-INT-${newUserId.toString().padStart(3, '0')}`;
        const [tlRows] = await connection.query(`SELECT u.id FROM users u
       JOIN team_leader_profiles tlp ON tlp.user_id = u.id
       WHERE u.role = 'team_leader' AND u.is_active = 1 AND u.deleted_at IS NULL
         AND tlp.department_id = ?
       ORDER BY u.id ASC LIMIT 1`, [departmentId]);
        const assignedTl = tlRows.length > 0 ? tlRows[0].id : null;
        await connection.query(`INSERT INTO intern_profiles (user_id, intern_code, department_id, batch_id, assigned_team_leader_id, internship_start_date, status, created_at, updated_at)
       VALUES (?, ?, ?, NULL, ?, CURDATE(), 'active', NOW(), NOW())`, [newUserId, code, departmentId, assignedTl]);
        await connection.commit();
        const token = jwt.sign({ id: newUserId, role: cleanRole, email: emailLower }, JWT_SECRET, { expiresIn: '24h', algorithm: 'HS256' });
        await logAuditEvent(newUserId, 'USER_REGISTER_SELF', 'users', newUserId, null, { name, role: cleanRole }, req);
        res.status(201).json({
            message: 'Account created successfully',
            token,
            user: {
                id: newUserId,
                name: name.trim(),
                email: emailLower,
                role: cleanRole,
                is_active: true,
            },
        });
    }
    catch (error) {
        await connection.rollback();
        console.error('Registration error:', error);
        res.status(500).json({ error: 'Failed to create user account' });
    }
    finally {
        connection.release();
    }
}
