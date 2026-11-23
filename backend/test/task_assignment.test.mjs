import { test, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

const { pool } = await import('../src/config/db.ts');
const {
  getInternDashboardMetrics,
  getAssignedCourses,
  getAssignedTasks,
  submitTaskSolution,
  getCertificateData,
} = await import('../src/controllers/intern.controller.ts');
const {
  createTask,
  assignTaskToInterns,
} = await import('../src/controllers/team_leader.controller.ts');
const originalQuery = pool.query;
const originalGetConnection = pool.getConnection;
const queries = [];
const connectionQueries = [];
let authorizedInternIds;

const app = express();
app.use(express.json());
app.use((req, res, next) => {
  req.user = { id: 9001, role: 'intern' };
  next();
});
app.get('/dashboard', getInternDashboardMetrics);
app.get('/courses', getAssignedCourses);
app.get('/tasks', getAssignedTasks);
app.get('/certificate', getCertificateData);
app.post('/submit', submitTaskSolution);
app.post('/tl/tasks', (req, res, next) => {
  req.user = { id: 700, role: 'team_leader' };
  next();
}, createTask);
app.post('/tl/tasks/:id/assign', (req, res, next) => {
  req.user = { id: 700, role: 'team_leader' };
  next();
}, assignTaskToInterns);
app.use((error, req, res, next) => res.status(500).json({ error: 'Request failed' }));
const server = app.listen(0, '127.0.0.1');
await new Promise((resolve) => server.on('listening', resolve));
const base = `http://127.0.0.1:${server.address().port}`;

beforeEach(() => {
  queries.length = 0;
  connectionQueries.length = 0;
  authorizedInternIds = new Set([901, 902]);
  pool.query = async (sql, values = []) => {
    queries.push({ sql, values });
    if (sql.includes('FROM users u') && sql.includes('JOIN intern_profiles ip')) {
      return [[{
        id: 9001,
        name: 'Test Intern',
        intern_code: 'INT-9001',
        department_id: 1,
        department_name: 'Engineering',
        internship_start_date: '2026-01-01',
      }], []];
    }
    if (sql.includes('AS assigned_courses')) {
      return [[{
        assigned_courses: 0,
        total_videos: 0,
        completed_videos: 0,
        total_materials: 0,
        completed_materials: 0,
      }], []];
    }
    if (sql.includes('AS total_tests')) {
      return [[{ total_tests: 0, pending_tests: 0 }], []];
    }
    if (sql.includes('FROM certificates WHERE intern_user_id')) return [[], []];
    if (sql.startsWith('SELECT ip.*')) {
      return [[{ department_id: 1, batch_id: 50 }], []];
    }
    if (sql.startsWith('SELECT department_id FROM intern_profiles')) {
      return [[{ department_id: 1 }], []];
    }
    if (sql.includes('duration_hours') && sql.includes('course_assignments')) {
      assert.deepEqual(values, [9001, 9001, 9001, 1, 9001]);
      return [[{ id: 17, title: 'Assigned course' }], []];
    }
    if (sql.includes('module_count') && sql.includes('course_assignments')) {
      assert.deepEqual(values, [9001, 9001, 9001, 1, 9001]);
      return [[{
        id: 17,
        title: 'Assigned course',
        video_count: 2,
        material_count: 1,
        completed_videos: 0,
        completed_materials: 0,
      }], []];
    }
    if (sql.includes('FROM courses c') && sql.includes('course_assignments')) {
      return [[], []];
    }
    if (sql.includes('COALESCE(SUM(total_watched_seconds)')) {
      return [[{ total_sec: 0 }], []];
    }
    if (sql.includes('FROM test_schedules ts')) {
      return [[{ count: 0 }], []];
    }
    if (sql.includes('FROM task_assignments ta')) {
      return [[{ count: 0 }], []];
    }
    if (sql.includes('FROM announcements a')) return [[], []];
    if (sql.includes('JOIN task_assignments ta')) return [[], []];
    if (sql.includes('SELECT ip.user_id')) {
      const requestedIds = values.filter((value) => value !== 700).map(Number);
      return [[...authorizedInternIds]
        .filter((id) => requestedIds.includes(id))
        .map((user_id) => ({ user_id })), []];
    }
    if (sql.startsWith('SELECT id FROM tasks WHERE id = ? AND created_by = ?')) {
      return [[{ id: Number(values[0]) }], []];
    }
    if (sql.startsWith('SELECT id FROM tasks WHERE id = ?')) {
      return [[{ id: Number(values[0]) }], []];
    }
    if (sql.startsWith('SELECT task_id FROM task_assignments')) return [[], []];
    if (sql.startsWith('INSERT IGNORE INTO task_assignments')) return [{ affectedRows: 1 }, []];
    if (sql.startsWith('INSERT INTO audit_logs')) return [{ affectedRows: 1 }, []];
    throw new Error(`Unexpected query: ${sql}`);
  };
  pool.getConnection = async () => ({
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, values = []) => {
      connectionQueries.push({ sql, values });
      if (sql.startsWith('INSERT INTO tasks')) return [{ insertId: 77 }, []];
      if (sql.startsWith('INSERT INTO task_assignments')) return [{ affectedRows: 1 }, []];
      throw new Error(`Unexpected connection query: ${sql}`);
    },
  });
});

after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
  pool.query = originalQuery;
  pool.getConnection = originalGetConnection;
  await pool.end();
});

test('dashboard ignores legacy global tasks without explicit intern assignments', async () => {
  const response = await fetch(`${base}/dashboard`);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.metrics.pending_tasks_count, 0);
  assert.equal(payload.metrics.assigned_courses_count, 1);

  const taskQuery = queries.find((query) => query.sql.includes('FROM task_assignments ta'));
  assert.ok(taskQuery);
  assert.match(taskQuery.sql, /ta\.user_id = \?/);
  assert.doesNotMatch(taskQuery.sql, /t\.course_id IS NULL|t\.batch_id IS NULL/);
});

test('assigned courses are returned for the intern and dashboard', async () => {
  const response = await fetch(`${base}/courses`);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.deepEqual(payload.courses.map((course) => course.id), [17]);
  assert.equal(payload.courses[0].progress_percent, 0);
});

test('certificate stays locked and does not report empty requirements as completed', async () => {
  const response = await fetch(`${base}/certificate`);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.eligible, false);
  assert.equal(payload.assigned_courses_count, 0);
  assert.equal(payload.progress_percent, 0);
  assert.equal(payload.total_tests_count, 0);
});

test('intern task list only returns explicit task assignments', async () => {
  const response = await fetch(`${base}/tasks`);
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).tasks, []);
  const taskQuery = queries.find((query) => query.sql.includes('JOIN task_assignments ta'));
  assert.ok(taskQuery);
  assert.match(taskQuery.sql, /ta\.user_id = \?/);
});

test('creating a task without selected interns is rejected', async () => {
  const response = await fetch(`${base}/tl/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Task', description: 'Instructions' }),
  });
  assert.equal(response.status, 400);
  assert.equal(connectionQueries.length, 0);
});

test('task creation atomically assigns only the selected active team interns', async () => {
  const response = await fetch(`${base}/tl/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      intern_ids: [901, 902],
      title: 'Task',
      description: 'Instructions',
    }),
  });
  assert.equal(response.status, 201);
  assert.equal(connectionQueries.filter((query) => query.sql.startsWith('INSERT INTO task_assignments')).length, 2);
  assert.deepEqual(
    connectionQueries
      .filter((query) => query.sql.startsWith('INSERT INTO task_assignments'))
      .map((query) => query.values),
    [[77, 901, 700], [77, 902, 700]],
  );
});

test('task assignment rejects interns outside the team', async () => {
  authorizedInternIds = new Set([901]);
  const response = await fetch(`${base}/tl/tasks/77/assign`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ intern_ids: [902] }),
  });
  assert.equal(response.status, 403);
  assert.equal(queries.some((query) => query.sql.startsWith('INSERT IGNORE INTO task_assignments')), false);
});

test('existing tasks can be assigned to selected team interns', async () => {
  const response = await fetch(`${base}/tl/tasks/77/assign`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ intern_ids: [901, 902] }),
  });
  assert.equal(response.status, 200);
  const assignmentQuery = queries.find((query) =>
    query.sql.startsWith('INSERT IGNORE INTO task_assignments'));
  assert.ok(assignmentQuery);
  assert.deepEqual(assignmentQuery.values, [77, 901, 700, 77, 902, 700]);
});

test('unassigned interns cannot submit task solutions', async () => {
  const response = await fetch(`${base}/submit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      task_id: 77,
      submission_text: 'My solution',
    }),
  });
  assert.equal(response.status, 403);
  assert.equal(queries.some((query) => query.sql.includes('task_submissions')), false);
});
