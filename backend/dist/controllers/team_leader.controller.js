import fs from 'fs';
import path from 'path';
import { pool } from '../config/db.js';
import { getMongoCollection } from '../config/mongodb.js';
import { logAuditEvent } from '../middleware/audit.js';
import { resolveStoredVideoDuration } from '../utils/videoDuration.js';
import { decodeUpload, InvalidUploadError, safeUploadName } from '../utils/upload.js';
// -----------------------------------------------------------------------------
// OWNERSHIP GUARDS
// -----------------------------------------------------------------------------
function isHrAdmin(req) {
    return req.user?.role === 'hr_admin';
}
function parsePositiveInt(value) {
    const num = Number(value);
    return Number.isInteger(num) && num > 0 ? num : null;
}
function removeStoredUpload(uploadPath) {
    if (!uploadPath || !uploadPath.startsWith('/uploads/'))
        return;
    try {
        const uploadsRoot = path.resolve('uploads');
        const absolute = path.resolve(uploadPath.replace(/^\/+/, ''));
        if (absolute.startsWith(uploadsRoot) && fs.existsSync(absolute)) {
            fs.unlinkSync(absolute);
        }
    }
    catch {
        // A missing file never blocks removing the database record.
    }
}
async function ownsQuiz(quizId, req) {
    if (isHrAdmin(req))
        return true;
    const [rows] = await pool.query('SELECT id FROM quizzes WHERE id = ? AND (created_by = ? OR created_by IS NULL OR created_by IN (SELECT id FROM users WHERE role IN ("hr_admin", "team_leader")))', [quizId, req.user.id]);
    return rows.length > 0;
}
async function ownsTask(taskId, req) {
    if (isHrAdmin(req))
        return true;
    const [rows] = await pool.query('SELECT id FROM tasks WHERE id = ? AND created_by = ?', [
        taskId,
        req.user.id,
    ]);
    return rows.length > 0;
}
function parseTaskInternIds(value) {
    if (!Array.isArray(value) || value.length === 0 || value.length > 500)
        return null;
    const parsed = value.map(parsePositiveInt);
    if (parsed.some((id) => id === null))
        return null;
    return [...new Set(parsed)];
}
async function canAssignTaskToInterns(internIds, req) {
    const placeholders = internIds.map(() => '?').join(',');
    const teamFilter = isHrAdmin(req) ? '' : ' AND ip.assigned_team_leader_id = ?';
    const params = isHrAdmin(req) ? internIds : [...internIds, req.user.id];
    const [rows] = await pool.query(`SELECT ip.user_id
     FROM intern_profiles ip
     JOIN users u ON u.id = ip.user_id
     WHERE ip.user_id IN (${placeholders})
       AND u.role = 'intern' AND u.is_active = 1 AND u.deleted_at IS NULL${teamFilter}`, params);
    return rows.length === internIds.length;
}
async function ownsSchedule(scheduleId, req) {
    if (isHrAdmin(req))
        return true;
    const [rows] = await pool.query('SELECT id FROM test_schedules WHERE id = ? AND (created_by = ? OR created_by IS NULL OR created_by IN (SELECT id FROM users WHERE role IN ("hr_admin", "team_leader")))', [scheduleId, req.user.id]);
    return rows.length > 0;
}
async function ownsQuestion(questionId, req) {
    if (isHrAdmin(req))
        return true;
    const [rows] = await pool.query('SELECT qq.id FROM quiz_questions qq JOIN quizzes q ON qq.quiz_id = q.id WHERE qq.id = ? AND q.created_by = ?', [questionId, req.user.id]);
    return rows.length > 0;
}
// -----------------------------------------------------------------------------
// TEAM LEADER DASHBOARD METRICS (6 KPIs)
// -----------------------------------------------------------------------------
export async function getTLDashboardMetrics(req, res) {
    const tlUserId = req.user.id;
    try {
        // 1. Assigned interns
        const [assignedInterns] = await pool.query(`SELECT ip.user_id 
       FROM intern_profiles ip 
       JOIN users u ON ip.user_id = u.id 
       WHERE ip.assigned_team_leader_id = ? AND u.deleted_at IS NULL`, [tlUserId]);
        const internUserIds = assignedInterns.map((i) => i.user_id);
        const assignedCount = internUserIds.length;
        let totalWatchSeconds = 0;
        let avgQuizScore = 0;
        let avgCompletionPercent = 0;
        if (assignedCount > 0) {
            const placeholders = internUserIds.map(() => '?').join(',');
            // 2. Video watch time
            const [watchRows] = await pool.query(`SELECT COALESCE(SUM(total_watched_seconds), 0) as total_sec 
         FROM video_watch_logs 
         WHERE user_id IN (${placeholders})`, internUserIds);
            totalWatchSeconds = Number(watchRows[0]?.total_sec || 0);
            // 3. Average quiz score (percentage of total marks)
            const [quizRows] = await pool.query(`SELECT COALESCE(AVG(qa.total_score / NULLIF(qz.total_marks, 0) * 100), 0) as avg_score 
         FROM quiz_attempts qa 
         JOIN quizzes qz ON qa.quiz_id = qz.id 
         WHERE qa.user_id IN (${placeholders}) AND qa.status = 'submitted'`, internUserIds);
            avgQuizScore = Math.round(Number(quizRows[0]?.avg_score || 0) * 10) / 10;
            // 4. Course completion avg
            const [compRows] = await pool.query(`SELECT COALESCE(AVG(completion_percentage), 0) as avg_comp 
         FROM video_watch_logs 
         WHERE user_id IN (${placeholders})`, internUserIds);
            avgCompletionPercent = Math.round(Number(compRows[0]?.avg_comp || 0) * 10) / 10;
        }
        // 5. Upcoming tests created by TL
        const [testRows] = await pool.query(`SELECT COUNT(*) as upcoming_tests 
       FROM test_schedules ts 
       WHERE ts.created_by = ? AND ts.end_window >= NOW() AND ts.is_active = 1`, [tlUserId]);
        // 6. Pending task assignments to review
        const [pendingTaskRows] = await pool.query(`SELECT COUNT(*) as pending_submissions 
       FROM task_submissions ts 
       JOIN tasks t ON ts.task_id = t.id 
       WHERE t.created_by = ? AND ts.status = 'pending'`, [tlUserId]);
        // Recent intern activity
        let recentActivities = [];
        if (assignedCount > 0) {
            const placeholders = internUserIds.map(() => '?').join(',');
            const [logs] = await pool.query(`SELECT vwl.updated_at, u.name as intern_name, v.title as video_title, vwl.completion_percentage 
         FROM video_watch_logs vwl 
         JOIN users u ON vwl.user_id = u.id 
         JOIN videos v ON vwl.video_id = v.id 
         WHERE vwl.user_id IN (${placeholders}) 
         ORDER BY vwl.updated_at DESC LIMIT 8`, internUserIds);
            recentActivities = logs;
        }
        res.json({
            metrics: {
                assigned_interns: assignedCount,
                average_completion_percentage: avgCompletionPercent,
                total_watch_minutes: Math.round(totalWatchSeconds / 60),
                upcoming_tests: testRows[0]?.upcoming_tests || 0,
                pending_assignments: pendingTaskRows[0]?.pending_submissions || 0,
                average_quiz_score: avgQuizScore,
            },
            recent_activities: recentActivities,
        });
    }
    catch (error) {
        console.error('TL Dashboard metrics error:', error);
        res.status(500).json({ error: 'Failed to retrieve Team Leader dashboard metrics' });
    }
}
// -----------------------------------------------------------------------------
// ASSIGNED INTERNS & PROGRESS DOSSIER
// -----------------------------------------------------------------------------
export async function getAssignedInterns(req, res) {
    const tlUserId = req.user.id;
    const { search } = req.query;
    try {
        let sql = `
      SELECT u.id, u.name, u.email, u.is_active, u.created_at, u.last_login_at,
             ip.department_id, ip.intern_code, ip.internship_start_date, ip.internship_end_date, ip.status as intern_status,
             ip.college_name, ip.emergency_contact,
             d.name as department_name, b.name as batch_name, b.batch_code,
             COALESCE(w.total_watch_seconds, 0) as total_watch_seconds,
             COALESCE(q.tests_completed, 0) as tests_completed,
             COALESCE(q.tests_passed, 0) as tests_passed,
             COALESCE(q.avg_test_score, 0) as avg_test_score
      FROM intern_profiles ip
      JOIN users u ON ip.user_id = u.id
      LEFT JOIN departments d ON ip.department_id = d.id
      LEFT JOIN batches b ON ip.batch_id = b.id
      LEFT JOIN (
        SELECT user_id, ROUND(SUM(total_watched_seconds)) as total_watch_seconds
        FROM video_watch_logs
        GROUP BY user_id
      ) w ON u.id = w.user_id
      LEFT JOIN (
        SELECT qa.user_id,
               COUNT(*) as tests_completed,
               SUM(CASE WHEN qa.is_passed = 1 THEN 1 ELSE 0 END) as tests_passed,
               ROUND(AVG(qa.total_score / NULLIF(qz.total_marks, 0) * 100), 1) as avg_test_score
        FROM quiz_attempts qa
        JOIN quizzes qz ON qa.quiz_id = qz.id
        WHERE qa.status = 'submitted'
        GROUP BY qa.user_id
      ) q ON u.id = q.user_id
      WHERE ip.assigned_team_leader_id = ? AND u.deleted_at IS NULL
    `;
        const params = [tlUserId];
        if (search) {
            sql += ' AND (u.name LIKE ? OR u.email LIKE ? OR ip.intern_code LIKE ?)';
            params.push(`%${search}%`, `%${search}%`, `%${search}%`);
        }
        sql += ' ORDER BY u.name ASC';
        const [rows] = await pool.query(sql, params);
        res.json({ interns: rows });
    }
    catch (error) {
        console.error('TL getAssignedInterns error:', error);
        res.status(500).json({ error: 'Failed to retrieve assigned interns' });
    }
}
export async function getInternDossier(req, res) {
    const internId = parsePositiveInt(req.params.intern_id);
    if (!internId) {
        res.status(400).json({ error: 'Invalid intern id' });
        return;
    }
    try {
        if (!isHrAdmin(req)) {
            const [assignment] = await pool.query('SELECT user_id FROM intern_profiles WHERE user_id = ? AND assigned_team_leader_id = ?', [internId, req.user.id]);
            if (assignment.length === 0) {
                res.status(404).json({ error: 'Intern not found' });
                return;
            }
        }
        // Intern profile & basic info
        const [userRows] = await pool.query(`SELECT u.id, u.name, u.email, u.is_active, u.last_login_at,
              ip.intern_code, ip.internship_start_date, ip.internship_end_date, ip.status,
              ip.college_name, ip.emergency_contact, ip.notes,
              d.name as department_name, b.name as batch_name
       FROM users u
       JOIN intern_profiles ip ON u.id = ip.user_id
       LEFT JOIN departments d ON ip.department_id = d.id
       LEFT JOIN batches b ON ip.batch_id = b.id
       WHERE u.id = ?`, [internId]);
        if (userRows.length === 0) {
            res.status(404).json({ error: 'Intern not found' });
            return;
        }
        // Video watch logs
        const [videoLogs] = await pool.query(`SELECT vwl.*, v.title as video_title, v.duration_seconds, cm.title as module_title, c.title as course_title
       FROM video_watch_logs vwl
       JOIN videos v ON vwl.video_id = v.id
       JOIN course_modules cm ON v.module_id = cm.id
       JOIN courses c ON cm.course_id = c.id
       WHERE vwl.user_id = ?
       ORDER BY vwl.updated_at DESC`, [internId]);
        // Quiz attempts
        const [quizAttempts] = await pool.query(`SELECT qa.*, q.title as quiz_title, q.total_marks, q.passing_marks
       FROM quiz_attempts qa
       JOIN quizzes q ON qa.quiz_id = q.id
       WHERE qa.user_id = ?
       ORDER BY qa.created_at DESC`, [internId]);
        // Task submissions
        const [tasks] = await pool.query(`SELECT ts.*, t.title as task_title, t.max_score, t.due_date
       FROM task_submissions ts
       JOIN tasks t ON ts.task_id = t.id
       WHERE ts.user_id = ?
       ORDER BY ts.submitted_at DESC`, [internId]);
        // Feedback given
        const [feedback] = await pool.query(`SELECT f.*, u.name as from_name
       FROM feedback f
       JOIN users u ON f.from_user_id = u.id
       WHERE f.to_user_id = ?
       ORDER BY f.created_at DESC`, [internId]);
        res.json({
            intern: userRows[0],
            video_logs: videoLogs,
            quiz_attempts: quizAttempts,
            tasks: tasks,
            feedback: feedback,
        });
    }
    catch (error) {
        console.error('TL getInternDossier error:', error);
        res.status(500).json({ error: 'Failed to retrieve intern dossier' });
    }
}
export async function assignCourse(req, res) {
    const { course_id, intern_ids, due_date } = req.body;
    const courseId = parsePositiveInt(course_id);
    const parsedIds = Array.isArray(intern_ids)
        ? intern_ids.map((value) => parsePositiveInt(value))
        : [];
    if (!courseId || parsedIds.length === 0 || parsedIds.some((id) => id === null)) {
        res.status(400).json({ error: 'course_id and intern_ids array are required' });
        return;
    }
    try {
        const targetIds = [...new Set(parsedIds)];
        const [courseRows] = await pool.query('SELECT department_id FROM courses WHERE id = ?', [courseId]);
        if (courseRows.length === 0) {
            res.status(404).json({ error: 'Course not found' });
            return;
        }
        const placeholders = targetIds.map(() => '?').join(',');
        const teamFilter = isHrAdmin(req) ? '' : ' AND ip.assigned_team_leader_id = ?';
        const internParams = isHrAdmin(req)
            ? targetIds
            : [...targetIds, req.user.id];
        const [internRows] = await pool.query(`SELECT ip.user_id, ip.department_id
       FROM intern_profiles ip
       JOIN users u ON u.id = ip.user_id
       WHERE ip.user_id IN (${placeholders})
         AND u.role = 'intern' AND u.is_active = 1 AND u.deleted_at IS NULL${teamFilter}`, internParams);
        if (internRows.length !== targetIds.length) {
            res.status(403).json({ error: 'You can only assign courses to active interns you manage' });
            return;
        }
        if (internRows.some((intern) => Number(intern.department_id) !== Number(courseRows[0].department_id))) {
            res.status(400).json({ error: 'Course and intern must belong to the same department' });
            return;
        }
        for (const internId of targetIds) {
            const [existing] = await pool.query(`SELECT id FROM course_assignments
         WHERE course_id = ? AND user_id = ? AND batch_id IS NULL
         ORDER BY id ASC LIMIT 1`, [courseId, internId]);
            if (existing.length > 0) {
                await pool.query(`UPDATE course_assignments
           SET assigned_by = ?, due_date = ?, updated_at = NOW()
           WHERE course_id = ? AND user_id = ? AND batch_id IS NULL`, [req.user.id, due_date || null, courseId, internId]);
            }
            else {
                await pool.query(`INSERT INTO course_assignments (course_id, assigned_by, user_id, due_date, created_at, updated_at)
           VALUES (?, ?, ?, ?, NOW(), NOW())`, [courseId, req.user.id, internId, due_date || null]);
            }
        }
        await logAuditEvent(req.user?.id || null, 'ASSIGN_COURSE_TO_INTERNS', 'courses', courseId, null, { intern_ids: targetIds, due_date }, req);
        res.json({ message: `Course assigned to ${targetIds.length} intern(s) successfully` });
    }
    catch (error) {
        console.error('Assign course error:', error);
        res.status(500).json({ error: 'Failed to assign course' });
    }
}
// -----------------------------------------------------------------------------
// QUIZ & QUESTION BANK MANAGEMENT
// -----------------------------------------------------------------------------
export async function getQuizzes(req, res) {
    try {
        const params = [];
        let whereClause = '';
        if (!isHrAdmin(req)) {
            whereClause = 'WHERE (q.created_by = ? OR q.created_by IS NULL OR q.created_by IN (SELECT id FROM users WHERE role IN ("hr_admin", "team_leader")))';
            params.push(req.user.id);
        }
        const [rows] = await pool.query(`
      SELECT q.*, c.title as course_title, u.name as creator_name,
             (SELECT COUNT(*) FROM quiz_questions qq WHERE qq.quiz_id = q.id) as question_count,
             (SELECT COUNT(*) FROM quiz_questions qq WHERE qq.quiz_id = q.id AND qq.question_type <> 'short_answer') as mcq_count,
             (SELECT COUNT(*) FROM quiz_questions qq WHERE qq.quiz_id = q.id AND qq.question_type = 'short_answer') as qa_count
      FROM quizzes q
      LEFT JOIN courses c ON q.course_id = c.id
      LEFT JOIN users u ON q.created_by = u.id
      ${whereClause}
      ORDER BY q.id DESC
    `, params);
        res.json({ quizzes: rows });
    }
    catch (error) {
        console.error('TL getQuizzes error:', error);
        res.status(500).json({ error: 'Failed to retrieve quizzes' });
    }
}
export async function getQuizDetails(req, res) {
    const quizId = parsePositiveInt(req.params.id);
    if (!quizId) {
        res.status(400).json({ error: 'Invalid quiz id' });
        return;
    }
    try {
        if (!(await ownsQuiz(quizId, req))) {
            res.status(404).json({ error: 'Quiz not found' });
            return;
        }
        const [quizRows] = await pool.query(`SELECT q.*, c.title as course_title FROM quizzes q LEFT JOIN courses c ON q.course_id = c.id WHERE q.id = ?`, [quizId]);
        if (quizRows.length === 0) {
            res.status(404).json({ error: 'Quiz not found' });
            return;
        }
        const [questions] = await pool.query(`SELECT * FROM quiz_questions WHERE quiz_id = ? ORDER BY sort_order ASC, id ASC`, [quizId]);
        // Parse options JSON if needed
        for (const q of questions) {
            if (typeof q.options === 'string') {
                try {
                    q.options = JSON.parse(q.options);
                }
                catch (_) { }
            }
        }
        res.json({ quiz: quizRows[0], questions });
    }
    catch (error) {
        console.error('TL getQuizDetails error:', error);
        res.status(500).json({ error: 'Failed to retrieve quiz details' });
    }
}
export async function createQuiz(req, res) {
    const { course_id, title, instructions, total_marks, passing_marks, duration_minutes } = req.body;
    if (!title) {
        res.status(400).json({ error: 'Quiz title is required' });
        return;
    }
    try {
        const [result] = await pool.query(`INSERT INTO quizzes (course_id, created_by, title, instructions, total_marks, passing_marks, duration_minutes, is_active, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 1, NOW(), NOW())`, [
            course_id || null,
            req.user.id,
            title,
            instructions || '',
            total_marks || 100,
            passing_marks || 60,
            duration_minutes || 30,
        ]);
        res.status(201).json({ message: 'Quiz created successfully', quiz_id: result.insertId });
    }
    catch (error) {
        console.error('Create quiz error:', error);
        res.status(500).json({ error: 'Failed to create quiz' });
    }
}
export async function updateQuiz(req, res) {
    const quizId = parsePositiveInt(req.params.id);
    const { course_id, title, instructions, total_marks, passing_marks, duration_minutes } = req.body;
    if (!quizId) {
        res.status(400).json({ error: 'Invalid quiz id' });
        return;
    }
    try {
        if (!(await ownsQuiz(quizId, req))) {
            res.status(404).json({ error: 'Quiz not found' });
            return;
        }
        await pool.query(`UPDATE quizzes 
       SET course_id = ?, title = ?, instructions = ?, total_marks = ?, passing_marks = ?, duration_minutes = ?, updated_at = NOW()
       WHERE id = ?`, [
            course_id || null,
            title,
            instructions || '',
            total_marks || 100,
            passing_marks || 60,
            duration_minutes || 30,
            quizId,
        ]);
        res.json({ message: 'Question paper / Quiz updated successfully' });
    }
    catch (error) {
        console.error('Update quiz error:', error);
        res.status(500).json({ error: 'Failed to update quiz' });
    }
}
export async function deleteQuiz(req, res) {
    const quizId = parsePositiveInt(req.params.id);
    if (!quizId) {
        res.status(400).json({ error: 'Invalid quiz id' });
        return;
    }
    try {
        if (!(await ownsQuiz(quizId, req))) {
            res.status(404).json({ error: 'Quiz not found' });
            return;
        }
        await pool.query('DELETE FROM quiz_attempts WHERE quiz_id = ?', [quizId]);
        await pool.query('DELETE FROM quiz_questions WHERE quiz_id = ?', [quizId]);
        await pool.query('DELETE FROM test_schedule_interns WHERE schedule_id IN (SELECT id FROM test_schedules WHERE quiz_id = ?)', [quizId]);
        await pool.query('DELETE FROM test_schedules WHERE quiz_id = ?', [quizId]);
        await pool.query('DELETE FROM quizzes WHERE id = ?', [quizId]);
        res.json({ message: 'Question paper / Quiz deleted successfully' });
    }
    catch (error) {
        console.error('Delete quiz error:', error);
        res.status(500).json({ error: 'Failed to delete quiz' });
    }
}
export async function addQuizQuestion(req, res) {
    const { quiz_id, question_text, question_type, options, correct_answer, marks, explanation } = req.body;
    const quizId = parsePositiveInt(quiz_id);
    if (!quizId || !question_text || !correct_answer) {
        res.status(400).json({ error: 'quiz_id, question_text, and correct_answer are required' });
        return;
    }
    try {
        if (!(await ownsQuiz(quizId, req))) {
            res.status(404).json({ error: 'Quiz not found' });
            return;
        }
        const [maxOrder] = await pool.query('SELECT COALESCE(MAX(sort_order), 0) as max_order FROM quiz_questions WHERE quiz_id = ?', [quizId]);
        const nextOrder = (maxOrder[0]?.max_order || 0) + 1;
        const [result] = await pool.query(`INSERT INTO quiz_questions (quiz_id, question_text, question_type, options, correct_answer, marks, explanation, sort_order, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`, [
            quizId,
            question_text,
            question_type || 'single_choice',
            JSON.stringify(options || []),
            correct_answer,
            marks || 10,
            explanation || '',
            nextOrder,
        ]);
        res.status(201).json({ message: 'Question added successfully to question paper', question_id: result.insertId });
    }
    catch (error) {
        console.error('Add question error:', error);
        res.status(500).json({ error: 'Failed to add question' });
    }
}
export async function updateQuizQuestion(req, res) {
    const questionId = parsePositiveInt(req.params.question_id);
    const { question_text, question_type, options, correct_answer, marks, explanation } = req.body;
    if (!questionId) {
        res.status(400).json({ error: 'Invalid question id' });
        return;
    }
    try {
        if (!(await ownsQuestion(questionId, req))) {
            res.status(404).json({ error: 'Question not found' });
            return;
        }
        await pool.query(`UPDATE quiz_questions 
       SET question_text = ?, question_type = ?, options = ?, correct_answer = ?, marks = ?, explanation = ?, updated_at = NOW()
       WHERE id = ?`, [
            question_text,
            question_type || 'single_choice',
            JSON.stringify(options || []),
            correct_answer,
            marks || 10,
            explanation || '',
            questionId,
        ]);
        res.json({ message: 'Question updated successfully' });
    }
    catch (error) {
        console.error('Update question error:', error);
        res.status(500).json({ error: 'Failed to update question' });
    }
}
export async function reorderQuizQuestions(req, res) {
    const quizId = parsePositiveInt(req.params.id);
    const { ordered_ids } = req.body; // Array of question IDs in desired order: [12, 10, 14]
    if (!quizId) {
        res.status(400).json({ error: 'Invalid quiz id' });
        return;
    }
    if (!Array.isArray(ordered_ids)) {
        res.status(400).json({ error: 'ordered_ids array is required' });
        return;
    }
    try {
        if (!(await ownsQuiz(quizId, req))) {
            res.status(404).json({ error: 'Quiz not found' });
            return;
        }
        for (let index = 0; index < ordered_ids.length; index++) {
            const qId = parsePositiveInt(ordered_ids[index]);
            if (!qId)
                continue;
            await pool.query('UPDATE quiz_questions SET sort_order = ? WHERE id = ? AND quiz_id = ?', [index + 1, qId, quizId]);
        }
        res.json({ message: 'Question paper order rearranged successfully' });
    }
    catch (error) {
        console.error('Reorder questions error:', error);
        res.status(500).json({ error: 'Failed to arrange question paper order' });
    }
}
export async function deleteQuizQuestion(req, res) {
    const questionId = parsePositiveInt(req.params.question_id);
    if (!questionId) {
        res.status(400).json({ error: 'Invalid question id' });
        return;
    }
    try {
        if (!(await ownsQuestion(questionId, req))) {
            res.status(404).json({ error: 'Question not found' });
            return;
        }
        await pool.query('DELETE FROM quiz_questions WHERE id = ?', [questionId]);
        res.json({ message: 'Question deleted successfully' });
    }
    catch (error) {
        console.error('Delete question error:', error);
        res.status(500).json({ error: 'Failed to delete question' });
    }
}
// -----------------------------------------------------------------------------
// TEST SCHEDULING
// -----------------------------------------------------------------------------
export async function getTestSchedules(req, res) {
    try {
        const params = [];
        let whereClause = '';
        if (!isHrAdmin(req)) {
            whereClause = 'WHERE (ts.created_by = ? OR ts.created_by IS NULL OR ts.created_by IN (SELECT id FROM users WHERE role IN ("hr_admin", "team_leader")))';
            params.push(req.user.id);
        }
        const [rows] = await pool.query(`
      SELECT ts.*, q.title as quiz_title, q.duration_minutes, q.passing_marks, b.name as batch_name, b.batch_code, u.name as scheduler_name,
             (SELECT COUNT(*) FROM quiz_attempts qa WHERE qa.test_schedule_id = ts.id AND qa.needs_review = 1) as pending_reviews,
             (SELECT GROUP_CONCAT(u2.name ORDER BY u2.name SEPARATOR ', ') FROM test_schedule_interns ti JOIN users u2 ON u2.id = ti.user_id WHERE ti.schedule_id = ts.id) as assigned_interns
      FROM test_schedules ts
      JOIN quizzes q ON ts.quiz_id = q.id
      LEFT JOIN batches b ON ts.batch_id = b.id
      LEFT JOIN users u ON ts.created_by = u.id
      ${whereClause}
      ORDER BY ts.id DESC
    `, params);
        res.json({ schedules: rows });
    }
    catch (error) {
        console.error('TL getTestSchedules error:', error);
        res.status(500).json({ error: 'Failed to retrieve test schedules' });
    }
}
export async function createTestSchedule(req, res) {
    const { quiz_id, batch_id, intern_ids, start_window, end_window, max_attempts } = req.body;
    const quizId = parsePositiveInt(quiz_id);
    if (!quizId || !start_window || !end_window) {
        res.status(400).json({ error: 'quiz_id, start_window, and end_window are required' });
        return;
    }
    try {
        if (!(await ownsQuiz(quizId, req))) {
            res.status(404).json({ error: 'Quiz not found' });
            return;
        }
        // Resolve target: an explicit intern list, a batch, or global (null).
        const requestedInternIds = Array.isArray(intern_ids)
            ? intern_ids.map((v) => parsePositiveInt(v)).filter((v) => !!v)
            : [];
        let resolvedBatchId = null;
        let resolvedInternIds = [];
        if (requestedInternIds.length > 0) {
            const [internRows] = await pool.query(`SELECT u.id FROM users u JOIN intern_profiles ip ON ip.user_id = u.id
         WHERE u.id IN (?) AND u.role = 'intern' AND u.deleted_at IS NULL AND u.is_active = 1`, [requestedInternIds]);
            resolvedInternIds = internRows.map((r) => Number(r.id));
            if (resolvedInternIds.length === 0) {
                res.status(400).json({ error: 'Selected intern(s) not found or inactive' });
                return;
            }
        }
        else if (batch_id != null) {
            const batchId = parsePositiveInt(batch_id);
            if (batchId) {
                const [batchRows] = await pool.query('SELECT id FROM batches WHERE id = ?', [batchId]);
                if (batchRows.length === 0) {
                    // Backward/forward compatibility: clients may send an intern user id here.
                    const [internRows] = await pool.query(`SELECT u.id FROM users u JOIN intern_profiles ip ON ip.user_id = u.id
             WHERE u.id = ? AND u.role = 'intern' AND u.deleted_at IS NULL AND u.is_active = 1`, [batchId]);
                    if (internRows.length === 0) {
                        res.status(400).json({ error: 'Selected batch or intern not found' });
                        return;
                    }
                    resolvedInternIds = [batchId];
                }
                else {
                    resolvedBatchId = batchId;
                }
            }
        }
        const [result] = await pool.query(`INSERT INTO test_schedules (quiz_id, batch_id, created_by, start_window, end_window, max_attempts, is_active, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 1, NOW(), NOW())`, [quizId, resolvedBatchId, req.user.id, start_window, end_window, max_attempts || 1]);
        if (resolvedInternIds.length > 0) {
            await pool.query('INSERT INTO test_schedule_interns (schedule_id, user_id) VALUES ?', [resolvedInternIds.map((id) => [result.insertId, id])]);
        }
        res.status(201).json({ message: 'Online test scheduled successfully', schedule_id: result.insertId });
    }
    catch (error) {
        console.error('Create schedule error:', error);
        res.status(500).json({ error: 'Failed to schedule test' });
    }
}
export async function deleteTestSchedule(req, res) {
    const scheduleId = parsePositiveInt(req.params.schedule_id);
    if (!scheduleId) {
        res.status(400).json({ error: 'Invalid schedule id' });
        return;
    }
    try {
        if (!(await ownsSchedule(scheduleId, req))) {
            res.status(404).json({ error: 'Test schedule not found' });
            return;
        }
        await pool.query('DELETE FROM quiz_attempts WHERE test_schedule_id = ?', [scheduleId]);
        await pool.query('DELETE FROM test_schedule_interns WHERE schedule_id = ?', [scheduleId]);
        await pool.query('DELETE FROM test_schedules WHERE id = ?', [scheduleId]);
        res.json({ message: 'Test schedule cancelled and deleted successfully' });
    }
    catch (error) {
        console.error('Delete schedule error:', error);
        res.status(500).json({ error: 'Failed to delete test schedule' });
    }
}
export async function getScheduleAttempts(req, res) {
    const scheduleId = parsePositiveInt(req.params.schedule_id);
    if (!scheduleId) {
        res.status(400).json({ error: 'Invalid schedule id' });
        return;
    }
    try {
        if (!(await ownsSchedule(scheduleId, req))) {
            res.status(404).json({ error: 'Test schedule not found' });
            return;
        }
        const [rows] = await pool.query(`SELECT qa.id, qa.user_id, qa.status, qa.total_score, qa.is_passed, qa.needs_review,
              qa.submitted_answers, qa.review_data, qa.reviewed_at, qa.start_time, qa.end_time,
              u.name as intern_name, ip.intern_code
       FROM quiz_attempts qa
       JOIN users u ON qa.user_id = u.id
       LEFT JOIN intern_profiles ip ON u.id = ip.user_id
       WHERE qa.test_schedule_id = ?
       ORDER BY qa.needs_review DESC, qa.id DESC`, [scheduleId]);
        for (const row of rows) {
            if (typeof row.submitted_answers === 'string') {
                try {
                    row.submitted_answers = JSON.parse(row.submitted_answers);
                }
                catch (_) { }
            }
            if (typeof row.review_data === 'string') {
                try {
                    row.review_data = JSON.parse(row.review_data);
                }
                catch (_) { }
            }
        }
        res.json({ attempts: rows });
    }
    catch (error) {
        console.error('TL getScheduleAttempts error:', error);
        res.status(500).json({ error: 'Failed to retrieve attempt answers' });
    }
}
export async function reviewQuizAttempt(req, res) {
    const attemptId = parsePositiveInt(req.params.attempt_id);
    const { reviews } = req.body;
    if (!attemptId) {
        res.status(400).json({ error: 'Invalid attempt id' });
        return;
    }
    if (!Array.isArray(reviews)) {
        res.status(400).json({ error: 'reviews array is required' });
        return;
    }
    try {
        const [attemptRows] = await pool.query('SELECT * FROM quiz_attempts WHERE id = ?', [attemptId]);
        if (attemptRows.length === 0) {
            res.status(404).json({ error: 'Attempt not found' });
            return;
        }
        const attempt = attemptRows[0];
        if (!(await ownsQuiz(attempt.quiz_id, req))) {
            res.status(404).json({ error: 'Attempt not found' });
            return;
        }
        if (Number(attempt.needs_review) !== 1) {
            res.status(400).json({ error: 'This attempt is not awaiting review. It may already be reviewed.' });
            return;
        }
        const [quizRows] = await pool.query('SELECT * FROM quizzes WHERE id = ?', [attempt.quiz_id]);
        const quiz = quizRows[0];
        const [questions] = await pool.query('SELECT id, marks, question_type, correct_answer FROM quiz_questions WHERE quiz_id = ?', [attempt.quiz_id]);
        const answers = typeof attempt.submitted_answers === 'string'
            ? JSON.parse(attempt.submitted_answers)
            : (attempt.submitted_answers || {});
        const reviewMarks = new Map();
        for (const r of reviews) {
            const qid = Number(r.question_id);
            const marks = Math.max(0, Number(r.marks) || 0);
            reviewMarks.set(qid, marks);
        }
        let totalScore = 0;
        const reviewData = {};
        for (const q of questions) {
            const maxMarks = Number(q.marks || 0);
            if (q.question_type === 'short_answer') {
                if (!reviewMarks.has(q.id)) {
                    res.status(400).json({ error: 'Marks are required for every written answer' });
                    return;
                }
                const awarded = Math.min(maxMarks, reviewMarks.get(q.id) || 0);
                totalScore += awarded;
                reviewData[q.id] = { marks_awarded: awarded, max_marks: maxMarks };
                continue;
            }
            const userAnswer = String(answers[q.id] || '').trim().toLowerCase();
            const correctAnswer = String(q.correct_answer || '').trim().toLowerCase();
            if (userAnswer !== '' && userAnswer === correctAnswer) {
                totalScore += maxMarks;
            }
        }
        const totalMarks = Number(quiz.total_marks) || questions.reduce((sum, q) => sum + Number(q.marks || 0), 0);
        const scorePercentage = totalMarks > 0 ? (totalScore / totalMarks) * 100 : 0;
        const isPassed = scorePercentage >= Number(quiz.passing_marks || 60);
        await pool.query(`UPDATE quiz_attempts
       SET total_score = ?, is_passed = ?, needs_review = 0, review_data = ?, reviewed_at = NOW(), updated_at = NOW()
       WHERE id = ?`, [totalScore, isPassed ? 1 : 0, JSON.stringify(reviewData), attemptId]);
        await logAuditEvent(req.user.id, 'REVIEW_QUIZ_ATTEMPT', 'quiz_attempts', attemptId, null, { total_score: totalScore, is_passed: isPassed }, req);
        res.json({
            message: 'Written answers reviewed and final score updated',
            total_score: totalScore,
            is_passed: isPassed,
            review_data: reviewData,
        });
    }
    catch (error) {
        console.error('TL reviewQuizAttempt error:', error);
        res.status(500).json({ error: 'Failed to save review' });
    }
}
export async function getQuizResults(req, res) {
    const { quiz_id } = req.query;
    try {
        let sql = `
      SELECT qa.*, u.name as intern_name, u.email as intern_email, ip.intern_code,
             q.title as quiz_title, q.passing_marks, q.total_marks
      FROM quiz_attempts qa
      JOIN users u ON qa.user_id = u.id
      JOIN intern_profiles ip ON u.id = ip.user_id
      JOIN quizzes q ON qa.quiz_id = q.id
      WHERE 1=1
    `;
        const params = [];
        if (quiz_id) {
            const quizId = parsePositiveInt(quiz_id);
            if (!quizId) {
                res.status(400).json({ error: 'Invalid quiz id' });
                return;
            }
            sql += ' AND qa.quiz_id = ?';
            params.push(quizId);
        }
        if (!isHrAdmin(req)) {
            sql += ' AND q.created_by = ?';
            params.push(req.user.id);
        }
        sql += ' ORDER BY qa.created_at DESC';
        const [rows] = await pool.query(sql, params);
        res.json({ results: rows });
    }
    catch (error) {
        console.error('TL getQuizResults error:', error);
        res.status(500).json({ error: 'Failed to retrieve quiz results' });
    }
}
// -----------------------------------------------------------------------------
// PRACTICAL TASKS & SUBMISSIONS
// -----------------------------------------------------------------------------
export async function getTasks(req, res) {
    try {
        const params = [];
        let whereClause = '';
        if (!isHrAdmin(req)) {
            whereClause = 'WHERE t.created_by = ?';
            params.push(req.user.id);
        }
        const [rows] = await pool.query(`
      SELECT t.*, c.title as course_title, b.name as batch_name, u.name as creator_name,
             (SELECT COUNT(*) FROM task_assignments ta WHERE ta.task_id = t.id) as assigned_intern_count,
             (SELECT COUNT(*) FROM task_submissions ts WHERE ts.task_id = t.id) as total_submissions,
             (SELECT COUNT(*) FROM task_submissions ts WHERE ts.task_id = t.id AND ts.status = 'pending') as pending_submissions
      FROM tasks t
      LEFT JOIN courses c ON t.course_id = c.id
      LEFT JOIN batches b ON t.batch_id = b.id
      LEFT JOIN users u ON t.created_by = u.id
      ${whereClause}
      ORDER BY t.id DESC
    `, params);
        res.json({ tasks: rows });
    }
    catch (error) {
        console.error('TL getTasks error:', error);
        res.status(500).json({ error: 'Failed to retrieve tasks' });
    }
}
export async function createTask(req, res) {
    const { course_id, title, description, attachment_path, due_date, max_score } = req.body;
    const taskTitle = typeof title === 'string' ? title.trim() : '';
    const taskDescription = typeof description === 'string' ? description.trim() : '';
    const internIds = parseTaskInternIds(req.body.intern_ids);
    const courseId = course_id == null ? null : parsePositiveInt(course_id);
    if (!taskTitle || taskTitle.length > 255 || !taskDescription) {
        res.status(400).json({ error: 'Title and description are required' });
        return;
    }
    if (!internIds) {
        res.status(400).json({ error: 'Select at least one valid intern' });
        return;
    }
    if (course_id != null && !courseId) {
        res.status(400).json({ error: 'Invalid course id' });
        return;
    }
    try {
        if (!(await canAssignTaskToInterns(internIds, req))) {
            res.status(403).json({ error: 'You can only assign tasks to active interns you manage' });
            return;
        }
        const connection = await pool.getConnection();
        let taskId;
        try {
            await connection.beginTransaction();
            const [result] = await connection.query(`INSERT INTO tasks (course_id, batch_id, created_by, title, description, attachment_path, due_date, max_score, created_at, updated_at)
         VALUES (?, NULL, ?, ?, ?, ?, ?, ?, NOW(), NOW())`, [
                courseId,
                req.user.id,
                taskTitle,
                taskDescription,
                typeof attachment_path === 'string' && attachment_path.trim() ? attachment_path.trim() : null,
                due_date || null,
                parsePositiveInt(max_score) || 100,
            ]);
            taskId = Number(result.insertId);
            for (const internId of internIds) {
                await connection.query('INSERT INTO task_assignments (task_id, user_id, assigned_by) VALUES (?, ?, ?)', [taskId, internId, req.user.id]);
            }
            await connection.commit();
        }
        catch (error) {
            await connection.rollback();
            throw error;
        }
        finally {
            connection.release();
        }
        await logAuditEvent(req.user.id, 'CREATE_AND_ASSIGN_TASK', 'tasks', taskId, null, {
            intern_ids: internIds,
        }, req);
        res.status(201).json({ message: `Task assigned to ${internIds.length} intern(s) successfully`, task_id: taskId });
    }
    catch (error) {
        console.error('Create task error:', error);
        res.status(500).json({ error: 'Failed to assign practical task' });
    }
}
export async function assignTaskToInterns(req, res) {
    const taskId = parsePositiveInt(req.params.id);
    const internIds = parseTaskInternIds(req.body.intern_ids);
    if (!taskId || !internIds) {
        res.status(400).json({ error: 'A valid task id and at least one intern id are required' });
        return;
    }
    try {
        if (!(await ownsTask(taskId, req))) {
            res.status(404).json({ error: 'Task not found' });
            return;
        }
        const [taskRows] = await pool.query('SELECT id FROM tasks WHERE id = ?', [taskId]);
        if (taskRows.length === 0) {
            res.status(404).json({ error: 'Task not found' });
            return;
        }
        if (!(await canAssignTaskToInterns(internIds, req))) {
            res.status(403).json({ error: 'You can only assign tasks to active interns you manage' });
            return;
        }
        const values = internIds.flatMap((internId) => [taskId, internId, req.user.id]);
        const [result] = await pool.query(`INSERT IGNORE INTO task_assignments (task_id, user_id, assigned_by)
       VALUES ${internIds.map(() => '(?, ?, ?)').join(', ')}`, values);
        await logAuditEvent(req.user.id, 'ASSIGN_TASK_TO_INTERNS', 'tasks', taskId, null, {
            intern_ids: internIds,
        }, req);
        const assignedCount = Number(result.affectedRows || 0);
        res.json({
            message: assignedCount > 0
                ? `Task assigned to ${assignedCount} intern(s) successfully`
                : 'Those interns are already assigned to this task',
            assigned_count: assignedCount,
        });
    }
    catch (error) {
        console.error('Assign task error:', error);
        res.status(500).json({ error: 'Failed to assign task' });
    }
}
export async function deleteTask(req, res) {
    const taskId = parsePositiveInt(req.params.id);
    if (!taskId) {
        res.status(400).json({ error: 'Invalid task id' });
        return;
    }
    try {
        if (!(await ownsTask(taskId, req))) {
            res.status(404).json({ error: 'Task not found' });
            return;
        }
        const [existing] = await pool.query('SELECT id, title FROM tasks WHERE id = ?', [taskId]);
        await pool.query('DELETE FROM task_submissions WHERE task_id = ?', [taskId]);
        await pool.query('DELETE FROM tasks WHERE id = ?', [taskId]);
        await logAuditEvent(req.user.id, 'DELETE_TASK', 'tasks', taskId, existing[0] || null, null, req);
        res.json({ message: 'Task deleted successfully' });
    }
    catch (error) {
        console.error('TL deleteTask error:', error);
        res.status(500).json({ error: 'Failed to delete task' });
    }
}
export async function getTaskSubmissions(req, res) {
    const taskId = parsePositiveInt(req.params.task_id);
    if (!taskId) {
        res.status(400).json({ error: 'Invalid task id' });
        return;
    }
    try {
        if (!(await ownsTask(taskId, req))) {
            res.status(404).json({ error: 'Task not found' });
            return;
        }
        const [rows] = await pool.query(`SELECT ts.*, u.name as intern_name, u.email as intern_email, ip.intern_code, t.title as task_title, t.max_score
       FROM task_submissions ts
       JOIN users u ON ts.user_id = u.id
       JOIN intern_profiles ip ON u.id = ip.user_id
       JOIN tasks t ON ts.task_id = t.id
       WHERE ts.task_id = ?
       ORDER BY ts.submitted_at DESC`, [taskId]);
        res.json({ submissions: rows });
    }
    catch (error) {
        console.error('TL getTaskSubmissions error:', error);
        res.status(500).json({ error: 'Failed to retrieve task submissions' });
    }
}
export async function gradeTaskSubmission(req, res) {
    const submissionId = parsePositiveInt(req.params.submission_id);
    const { score, tl_feedback, status } = req.body;
    if (!submissionId) {
        res.status(400).json({ error: 'Invalid submission id' });
        return;
    }
    if (score === undefined) {
        res.status(400).json({ error: 'Score is required' });
        return;
    }
    try {
        if (!isHrAdmin(req)) {
            const [ownership] = await pool.query(`SELECT ts.id FROM task_submissions ts
         JOIN tasks t ON ts.task_id = t.id
         WHERE ts.id = ? AND t.created_by = ?`, [submissionId, req.user.id]);
            if (ownership.length === 0) {
                res.status(404).json({ error: 'Submission not found' });
                return;
            }
        }
        await pool.query(`UPDATE task_submissions 
       SET score = ?, tl_feedback = ?, status = ?, graded_by = ?, graded_at = NOW(), updated_at = NOW()
       WHERE id = ?`, [score, tl_feedback || '', status || 'graded', req.user.id, submissionId]);
        await logAuditEvent(req.user?.id || null, 'GRADE_TASK_SUBMISSION', 'task_submissions', submissionId, null, { score, tl_feedback, status }, req);
        res.json({ message: 'Task submission evaluated and graded successfully' });
    }
    catch (error) {
        console.error('Grade task error:', error);
        res.status(500).json({ error: 'Failed to grade task submission' });
    }
}
// -----------------------------------------------------------------------------
// FEEDBACK
// -----------------------------------------------------------------------------
export async function submitFeedback(req, res) {
    const { to_user_id, context_type, context_id, rating, comments } = req.body;
    const toUserId = Number(to_user_id);
    const commentText = typeof comments === 'string' ? comments.trim() : '';
    const score = Number(rating);
    if (!Number.isInteger(toUserId) || toUserId <= 0 || !commentText) {
        res.status(400).json({ error: 'to_user_id and comments are required' });
        return;
    }
    if (commentText.length > 2000) {
        res.status(400).json({ error: 'Feedback must be 2000 characters or fewer' });
        return;
    }
    if (!Number.isInteger(score) || score < 1 || score > 5) {
        res.status(400).json({ error: 'Rating must be between 1 and 5 stars' });
        return;
    }
    try {
        const [internRows] = await pool.query(`SELECT id FROM users WHERE id = ? AND role = 'intern' AND deleted_at IS NULL`, [toUserId]);
        if (internRows.length === 0) {
            res.status(400).json({ error: 'Feedback can only be given to an active intern' });
            return;
        }
        if (req.user.role !== 'hr_admin') {
            const [assignedRows] = await pool.query(`SELECT id FROM intern_profiles WHERE user_id = ? AND assigned_team_leader_id = ? LIMIT 1`, [toUserId, req.user.id]);
            if (assignedRows.length === 0) {
                res.status(403).json({ error: 'You can only give feedback to interns assigned to you' });
                return;
            }
        }
        const [result] = await pool.query(`INSERT INTO feedback (from_user_id, to_user_id, context_type, context_id, rating, comments, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, NOW(), NOW())`, [
            req.user.id,
            toUserId,
            context_type || 'internship',
            context_id || null,
            score,
            commentText,
        ]);
        await logAuditEvent(req.user.id, 'SUBMIT_FEEDBACK', 'feedback', result.insertId, null, { to_user_id: toUserId, rating: score }, req);
        res.status(201).json({ message: 'Feedback submitted successfully', feedback_id: result.insertId });
    }
    catch (error) {
        console.error('Submit feedback error:', error);
        res.status(500).json({ error: 'Failed to submit feedback' });
    }
}
// -----------------------------------------------------------------------------
// TEAM LEADER SOP MANAGEMENT & DIRECT FILE UPLOAD (PDF, EXCEL, PHOTO)
// -----------------------------------------------------------------------------
export async function getSops(req, res) {
    try {
        const [rows] = await pool.query(`SELECT lm.*, cm.title as module_title, c.title as course_title
       FROM learning_materials lm
       LEFT JOIN course_modules cm ON lm.module_id = cm.id
       LEFT JOIN courses c ON cm.course_id = c.id
       WHERE lm.material_type IN ('sop', 'pdf', 'doc', 'ppt')
       ORDER BY lm.id DESC`);
        // Merge with MongoDB rich metadata if available
        try {
            const sopsColl = getMongoCollection('sops');
            const mongoSops = await sopsColl.find({}).toArray();
            const mongoMap = new Map();
            mongoSops.forEach((m) => mongoMap.set(m.title, m));
            const enriched = rows.map((r) => {
                const extra = mongoMap.get(r.title);
                return {
                    ...r,
                    author: extra?.author || 'KGPL Engineering & TL Lead',
                    date: extra?.date || r.created_at,
                    version: extra?.version || '1.0',
                    summary: extra?.summary || r.title,
                    steps: extra?.steps || [],
                    markdownContent: extra?.markdownContent || '',
                    fileType: extra?.fileType || r.material_type,
                };
            });
            res.json({ sops: enriched });
            return;
        }
        catch (_) {
            res.json({ sops: rows });
        }
    }
    catch (error) {
        console.error('TL getSops error:', error);
        res.status(500).json({ error: 'Failed to retrieve SOPs' });
    }
}
export async function uploadSop(req, res) {
    const tlUserId = req.user.id;
    const tlName = req.user.name || 'Team Leader';
    const { title, category, module_id, course_id, file_name, file_data, // Base64 string
    file_type, // 'pdf', 'excel', 'photo', 'doc', 'sop'
    markdown_content, summary, version, } = req.body;
    if (!title || !title.trim()) {
        res.status(400).json({ error: 'SOP title is required' });
        return;
    }
    let writtenUploadPath = null;
    try {
        const uploadDir = path.resolve('uploads', 'sops');
        if (!fs.existsSync(uploadDir)) {
            fs.mkdirSync(uploadDir, { recursive: true });
        }
        let savedFilePath = '';
        let fileSizeKb = 0;
        if (file_data && file_name) {
            const upload = decodeUpload(file_name, file_data, 'document');
            const safeName = safeUploadName(String(file_name), upload.extension);
            fs.writeFileSync(path.join(uploadDir, safeName), upload.buffer);
            savedFilePath = `/uploads/sops/${safeName}`;
            fileSizeKb = Math.round(upload.buffer.length / 1024);
        }
        else {
            // Save markdown as a markdown doc if no binary file was attached
            const markdownBody = String(markdown_content || `# ${title}\n\n${summary || ''}`);
            if (Buffer.byteLength(markdownBody, 'utf8') > 5 * 1024 * 1024) {
                res.status(400).json({ error: 'SOP text must be 5 MB or smaller' });
                return;
            }
            const safeName = `${Date.now()}_${String(title).replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 80)}.md`;
            const fullPath = path.join(uploadDir, safeName);
            fs.writeFileSync(fullPath, markdownBody);
            savedFilePath = `/uploads/sops/${safeName}`;
            fileSizeKb = Math.round(Buffer.byteLength(markdownBody, 'utf8') / 1024) || 2;
        }
        writtenUploadPath = savedFilePath;
        // SOPs live in their own module, never inside a video lesson module.
        let targetModuleId = module_id ? Number(module_id) : null;
        if (targetModuleId) {
            const [modCheck] = await pool.query('SELECT id FROM course_modules WHERE id = ?', [targetModuleId]);
            if (modCheck.length === 0)
                targetModuleId = null;
        }
        if (!targetModuleId) {
            let targetCourseId = course_id ? Number(course_id) : null;
            if (!targetCourseId) {
                const [firstCourse] = await pool.query('SELECT id FROM courses ORDER BY id ASC LIMIT 1');
                targetCourseId = firstCourse[0]?.id ?? null;
            }
            if (targetCourseId) {
                const [sopModule] = await pool.query(`SELECT id FROM course_modules WHERE course_id = ? AND title = 'SOPs & Study Material' ORDER BY id ASC LIMIT 1`, [targetCourseId]);
                if (sopModule.length > 0) {
                    targetModuleId = sopModule[0].id;
                }
                else {
                    const [createdModule] = await pool.query(`INSERT INTO course_modules (course_id, title, description, order_sequence, created_at, updated_at)
             VALUES (?, 'SOPs & Study Material', 'Standard operating procedures and study documents', 99, NOW(), NOW())`, [targetCourseId]);
                    targetModuleId = createdModule.insertId;
                }
            }
        }
        if (!targetModuleId) {
            removeStoredUpload(writtenUploadPath);
            res.status(400).json({ error: 'Create a course before uploading SOP documents' });
            return;
        }
        // Map file_type to MySQL enum ('sop','pdf','ppt','doc','external_link')
        let dbMaterialType = 'sop';
        if (file_type === 'pdf')
            dbMaterialType = 'pdf';
        else if (file_type === 'excel' || file_type === 'photo' || file_type === 'doc')
            dbMaterialType = 'doc';
        // Insert into MySQL learning_materials
        const [insertResult] = await pool.query(`INSERT INTO learning_materials 
        (module_id, title, material_type, file_path, file_size_kb, allow_download, order_sequence, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 1, 99, NOW(), NOW())`, [targetModuleId, title.trim(), dbMaterialType, savedFilePath, fileSizeKb]);
        const insertedId = insertResult.insertId;
        // Save into MongoDB NoSQL store
        try {
            const sopsColl = getMongoCollection('sops');
            await sopsColl.insertOne({
                id: insertedId,
                title: title.trim(),
                category: category || 'Enterprise Operations',
                author: tlName,
                version: version || '1.0',
                date: new Date().toLocaleDateString('en-US', { day: 'numeric', month: 'short', year: 'numeric' }),
                summary: summary || title.trim(),
                markdownContent: markdown_content || '',
                filePath: savedFilePath,
                fileName: file_name || `${title}.md`,
                fileType: file_type || 'sop',
                fileSizeKb,
                uploadedBy: { id: tlUserId, name: tlName },
                createdAt: new Date().toISOString(),
            });
        }
        catch (nosqlErr) {
            console.warn('MongoDB SOP logging warning:', nosqlErr);
        }
        await logAuditEvent(tlUserId, 'upload_sop', 'learning_materials', insertedId, null, { title, file_name, file_type, savedFilePath }, req);
        res.status(201).json({
            message: 'SOP document successfully uploaded and registered in portal',
            sop: {
                id: insertedId,
                title: title.trim(),
                file_path: savedFilePath,
                file_type: file_type || 'sop',
                file_size_kb: fileSizeKb,
                category: category || 'Enterprise Operations',
            },
        });
    }
    catch (error) {
        removeStoredUpload(writtenUploadPath);
        if (error instanceof InvalidUploadError) {
            res.status(400).json({ error: error.message });
            return;
        }
        console.error('TL uploadSop error:', error);
        res.status(500).json({ error: 'Failed to upload and register SOP document' });
    }
}
export async function deleteSop(req, res) {
    const { id } = req.params;
    const tlUserId = req.user.id;
    try {
        const [existing] = await pool.query('SELECT * FROM learning_materials WHERE id = ?', [id]);
        if (existing.length === 0) {
            res.status(404).json({ error: 'SOP not found' });
            return;
        }
        await pool.query('DELETE FROM learning_materials WHERE id = ?', [id]);
        removeStoredUpload(existing[0].file_path);
        // Also delete from MongoDB
        try {
            const sopsColl = getMongoCollection('sops');
            await sopsColl.deleteOne({ id: Number(id) });
        }
        catch (_) { }
        await logAuditEvent(tlUserId, 'delete_sop', 'learning_materials', Number(id), existing[0], null, req);
        res.json({ message: 'SOP successfully deleted' });
    }
    catch (error) {
        console.error('TL deleteSop error:', error);
        res.status(500).json({ error: 'Failed to delete SOP' });
    }
}
// -----------------------------------------------------------------------------
// TEAM LEADER VIDEO LESSON POSTING & UPLOAD TO INTERN CURRICULUM
// -----------------------------------------------------------------------------
export async function uploadVideo(req, res) {
    const tlUserId = req.user.id;
    let { module_id, course_id, title, description, video_url, file_name, file_data, duration_minutes } = req.body;
    if (!title || !title.trim()) {
        res.status(400).json({ error: 'Video title is required' });
        return;
    }
    let uploadedVideoPath = null;
    try {
        const videoUploadDir = path.resolve('uploads', 'videos');
        if (!fs.existsSync(videoUploadDir)) {
            fs.mkdirSync(videoUploadDir, { recursive: true });
        }
        let finalVideoPath = video_url || '';
        if (file_data && file_name) {
            const upload = decodeUpload(file_name, file_data, 'video');
            const safeName = safeUploadName(String(file_name), upload.extension);
            fs.writeFileSync(path.join(videoUploadDir, safeName), upload.buffer);
            finalVideoPath = `/uploads/videos/${safeName}`;
            uploadedVideoPath = finalVideoPath;
        }
        if (!finalVideoPath) {
            // Default fallback demo stream
            finalVideoPath = '/uploads/videos/zabbix_deployment_guide.mp4';
        }
        // Attach to module or course
        let targetModuleId = module_id ? Number(module_id) : null;
        if (!targetModuleId && course_id) {
            const [existingMods] = await pool.query('SELECT id FROM course_modules WHERE course_id = ? ORDER BY order_sequence ASC LIMIT 1', [course_id]);
            if (existingMods.length > 0) {
                targetModuleId = existingMods[0].id;
            }
        }
        if (!targetModuleId) {
            const [firstMod] = await pool.query('SELECT id FROM course_modules ORDER BY id ASC LIMIT 1');
            targetModuleId = firstMod.length > 0 ? firstMod[0].id : 4;
        }
        const durationSeconds = resolveStoredVideoDuration(finalVideoPath, (Number(duration_minutes) || 10) * 60);
        const [result] = await pool.query(`INSERT INTO videos 
        (module_id, title, description, video_path, duration_seconds, min_watch_percentage, order_sequence, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 80, 99, NOW(), NOW())`, [targetModuleId, title.trim(), description || '', finalVideoPath, durationSeconds]);
        await logAuditEvent(tlUserId, 'TL_POST_VIDEO', 'videos', result.insertId, null, { title, finalVideoPath, targetModuleId }, req);
        res.status(201).json({
            message: 'Video lesson successfully posted to intern curriculum',
            video_id: result.insertId,
            module_id: targetModuleId,
            video_path: finalVideoPath,
        });
    }
    catch (error) {
        removeStoredUpload(uploadedVideoPath);
        if (error instanceof InvalidUploadError) {
            res.status(400).json({ error: error.message });
            return;
        }
        console.error('TL uploadVideo error:', error);
        res.status(500).json({ error: 'Failed to post video to intern curriculum' });
    }
}
