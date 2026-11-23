import { test, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import express from 'express';

const originalCwd = process.cwd();
const sandbox = await fs.mkdtemp(path.join(os.tmpdir(), 'kgpl-video-access-'));
process.chdir(sandbox);
process.env.JWT_SECRET = crypto.randomBytes(32).toString('hex');
const { pool } = await import('../src/config/db.ts');
const { applySequentialAccess, getVideoAccess, resolveVideoUploadPath } = await import('../src/utils/videoAccess.ts');
const { getAssignedCourses, initVideoSession, recordVideoHeartbeat, getCoursePlaybackData, streamVideo } = await import('../src/controllers/intern.controller.ts');
const { assignCourse } = await import('../src/controllers/team_leader.controller.ts');
const { protectVideoUpload } = await import('../src/middleware/auth.ts');
const { isVideoUploadPath } = await import('../src/utils/upload.ts');
const originalQuery = pool.query;

const app = express();
app.use(express.json());
app.use('/uploads', protectVideoUpload, express.static(path.resolve('uploads')));
app.get('/stream/:video_id', streamVideo);
app.use((req, res, next) => { req.user = { id: 9001, role: 'intern' }; next(); });
app.get('/courses/:course_id', getCoursePlaybackData);
app.get('/my-courses', getAssignedCourses);
app.post('/init', initVideoSession);
app.post('/heartbeat', recordVideoHeartbeat);
app.post('/assign-course', (req, res, next) => {
  req.user = { id: 700, role: 'team_leader' };
  next();
}, assignCourse);
app.use((error, req, res, next) => res.status(error.status || 500).json({ error: 'Request failed' }));
const server = app.listen(0, '127.0.0.1');
await new Promise((resolve) => server.on('listening', resolve));
const base = `http://127.0.0.1:${server.address().port}`;

let videos;
let logs;
let queries;
let departmentAllowed;
let published;
let activeUser;
let sessionFresh;
let assigned;
let internDepartmentId;
let teamAssignmentAllowed;
let assignedCourseUsers;
let assignmentInsertCount;
let assignmentUpdateCount;

beforeEach(() => {
  videos = Array.from({ length: 5 }, (_, i) => ({ id: i + 1, title: `Lesson ${i + 1}`, module_id: 10, course_id: 20, order_sequence: 1, duration_seconds: 10, min_watch_percentage: 90, video_path: `/uploads/videos/lesson${i + 1}.mp4` }));
  videos.push({ ...videos[0], id: 6, module_id: 11, title: 'Other module first' });
  logs = new Map();
  queries = [];
  departmentAllowed = true;
  published = true;
  activeUser = true;
  sessionFresh = true;
  assigned = true;
  internDepartmentId = 1;
  teamAssignmentAllowed = true;
  assignedCourseUsers = new Set();
  assignmentInsertCount = 0;
  assignmentUpdateCount = 0;
  pool.query = async (sql, values = []) => {
    queries.push({ sql, values });
    if (sql.startsWith('SELECT department_id FROM courses WHERE id =')) {
      return [[{ department_id: 1 }], []];
    }
    if (sql.includes('SELECT ip.user_id, ip.department_id')) {
      return [teamAssignmentAllowed && values[0] === 9001 && values[values.length - 1] === 700
        ? [{ user_id: 9001, department_id: internDepartmentId }]
        : [], []];
    }
    if (sql.startsWith('SELECT id FROM course_assignments') && sql.includes('batch_id IS NULL')) {
      return [assignedCourseUsers.has(`${values[0]}:${values[1]}`) ? [{ id: 1 }] : [], []];
    }
    if (sql.startsWith('INSERT INTO course_assignments')) {
      assignmentInsertCount++;
      assignedCourseUsers.add(`${values[0]}:${values[2]}`);
      return [{ affectedRows: 1 }, []];
    }
    if (sql.startsWith('UPDATE course_assignments')) {
      assignmentUpdateCount++;
      return [{ affectedRows: 1 }, []];
    }
    if (sql.startsWith('INSERT INTO audit_logs')) return [{ affectedRows: 1 }, []];
    if (sql.includes('SELECT vwl.user_id')) {
      const log = logs.get(Number(values[0]));
      return [activeUser && sessionFresh && log?.session_token === values[1] ? [{ user_id: 9001 }] : [], []];
    }
    if (sql.includes('JOIN intern_profiles ip')) {
      const video = videos.find((v) => v.id === Number(values[1]));
      return [departmentAllowed && published && assigned && video ? [{ ...video }] : [], []];
    }
    if (sql.startsWith('SELECT id FROM course_assignments')) {
      return [assigned ? [{ id: 1 }] : [], []];
    }
    if (sql.startsWith('SELECT batch_id, department_id FROM intern_profiles')) {
      return [[{ batch_id: null, department_id: 1 }], []];
    }
    if (sql.includes('FROM courses c') && sql.includes('FROM course_assignments ca')) {
      assert.match(sql, /ca\.user_id = \?/);
      return [assigned ? [{ id: 20, title: 'Fixture course', video_count: 5, material_count: 0 }] : [], []];
    }
    if (sql.includes('FROM videos v') && (sql.includes('WHERE cm.course_id') || sql.includes('WHERE v.module_id'))) {
      const courseQuery = sql.includes('WHERE cm.course_id');
      const matchingVideos = courseQuery
        ? videos.filter((v) => v.course_id === Number(values[1])).sort((a, b) => a.module_id - b.module_id || a.order_sequence - b.order_sequence || a.id - b.id)
        : videos.filter((v) => v.module_id === Number(values[1])).sort((a, b) => a.order_sequence - b.order_sequence || a.id - b.id);
      if (courseQuery) assert.match(sql, /ORDER BY cm\.order_sequence ASC, cm\.id ASC, v\.order_sequence ASC, v\.id ASC/);
      return [matchingVideos.map((v) => ({ ...v, last_position_seconds: logs.get(v.id)?.last_position_seconds || 0, total_watched_seconds: logs.get(v.id)?.total_watched_seconds || 0, completion_percentage: logs.get(v.id)?.completion_percentage || 0, watch_count: logs.get(v.id)?.watch_count || 0, is_completed: logs.get(v.id)?.is_completed || 0 })), []];
    }
    if (sql.includes('SELECT c.*, d.name')) return [[{ id: 20, department_id: 1, title: 'Fixture course' }], []];
    if (sql.includes('SELECT department_id') && sql.includes('FROM intern_profiles')) return [[{ department_id: departmentAllowed ? 1 : 2, batch_id: null }], []];
    if (sql.includes('SELECT * FROM course_modules')) return [[{ id: 10, title: 'Module one' }, { id: 11, title: 'Module two' }], []];
    if (sql.includes('FROM learning_materials')) return [[], []];
    if (sql.startsWith('SELECT * FROM video_watch_logs')) {
      const log = logs.get(Number(values[1]));
      return [log && (values.length === 2 || log.session_token === values[2]) ? [{ ...log }] : [], []];
    }
    if (sql.startsWith('INSERT INTO video_watch_logs')) {
      const log = { id: Number(values[1]), session_token: values[2], last_position_seconds: 0, total_watched_seconds: 0, is_completed: 0, completion_percentage: 0, last_heartbeat_at: new Date(), watch_count: 1 };
      logs.set(log.id, log);
      return [{ insertId: log.id }, []];
    }
    if (sql.startsWith('UPDATE video_watch_logs SET session_token')) {
      const log = logs.get(Number(values[1]));
      log.session_token = values[0];
      log.watch_count++;
      log.last_heartbeat_at = new Date();
      return [{ affectedRows: 1 }, []];
    }
    if (sql.includes('UPDATE video_watch_logs')) {
      const log = logs.get(Number(values[4]));
      assert.match(sql, /WHERE id = \? AND session_token = \?/);
      assert.match(sql, /is_completed = GREATEST/);
      if (log.session_token !== values[5]) return [{ affectedRows: 0 }, []];
      Object.assign(log, { last_position_seconds: values[0], total_watched_seconds: Math.max(log.total_watched_seconds, values[1]), completion_percentage: Math.max(log.completion_percentage, values[2]), is_completed: Math.max(log.is_completed, values[3]), last_heartbeat_at: new Date() });
      return [{ affectedRows: 1 }, []];
    }
    if (sql.includes('INSERT INTO video_heartbeats') || sql.includes('INSERT INTO learning_progress')) return [{ affectedRows: 1 }, []];
    throw new Error(`Unexpected fixture query: ${sql}`);
  };
});

after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
  pool.query = originalQuery;
  await pool.end();
  process.chdir(originalCwd);
  await fs.rm(sandbox, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
});

async function post(route, body) {
  const response = await fetch(`${base}${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return { status: response.status, body: await response.json() };
}

function complete(id) {
  logs.set(id, { id, is_completed: 1, completion_percentage: 100, last_position_seconds: 10, total_watched_seconds: 10, session_token: crypto.randomBytes(32).toString('hex'), last_heartbeat_at: new Date(), watch_count: 1 });
}

test('all course lessons start locked except the first, including across modules', () => {
  const result = applySequentialAccess(videos);
  assert.deepEqual(result.map((v) => v.is_unlocked), [true, false, false, false, false, false]);
  assert.equal(result[5].required_video_id, 1);
  assert.equal(result[5].required_video_title, 'Lesson 1');
});

test('each completion opens exactly the next lesson while preserving earlier lessons', async () => {
  for (let completed = 0; completed < videos.length; completed++) {
    const access = await Promise.all(videos.map((v) => getVideoAccess(9001, v.id)));
    assert.deepEqual(access.map((v) => v.is_unlocked), videos.map((_, i) => i <= completed));
    complete(completed + 1);
  }
});

test('first video in a later module stays locked until earlier course videos are complete', async () => {
  assert.equal((await getVideoAccess(9001, 6)).is_unlocked, false);
  for (let id = 1; id <= 5; id++) complete(id);
  assert.equal((await getVideoAccess(9001, 6)).is_unlocked, true);
});

test('historically completed out-of-order lessons remain rewatchable but cannot skip gaps', async () => {
  complete(2);
  assert.equal((await getVideoAccess(9001, 2)).is_unlocked, true);
  assert.equal((await getVideoAccess(9001, 3)).is_unlocked, false);
  assert.equal((await getVideoAccess(9001, 3)).required_video_id, 1);
});

test('course response supplies locks and no source URLs or session tokens', async () => {
  complete(1);
  const response = await fetch(`${base}/courses/20`);
  assert.equal(response.status, 200);
  const { course } = await response.json();
  assert.deepEqual(course.modules[0].videos.map((v) => v.is_unlocked), [true, true, false, false, false]);
  assert.equal(course.modules[1].videos[0].is_unlocked, false);
  for (const module of course.modules) for (const video of module.videos) {
    assert.equal(video.video_path, null);
    assert.equal(video.session_token, undefined);
  }
});

test('unassigned courses cannot be opened or initialized', async () => {
  assigned = false;
  assert.equal((await fetch(`${base}/courses/20`)).status, 404);
  assert.equal((await post('/init', { video_id: 1 })).status, 404);
});

test('intern course list contains only assigned courses', async () => {
  assigned = false;
  const emptyResponse = await fetch(`${base}/my-courses`);
  assert.deepEqual((await emptyResponse.json()).courses, []);

  assigned = true;
  const assignedResponse = await fetch(`${base}/my-courses`);
  assert.deepEqual((await assignedResponse.json()).courses.map((course) => course.id), [20]);
});

test('batch-wide course assignments do not grant courses automatically', async () => {
  assigned = false;
  const response = await fetch(`${base}/my-courses`);
  assert.deepEqual((await response.json()).courses, []);
  const courseQuery = queries.find((query) => query.sql.includes('FROM courses c'));
  assert.ok(courseQuery);
  assert.doesNotMatch(courseQuery.sql, /ca\.batch_id/);
});

test('team leader assigns a course to their intern without duplicating assignment rows', async () => {
  const first = await post('/assign-course', { course_id: 20, intern_ids: [9001] });
  assert.equal(first.status, 200);
  const second = await post('/assign-course', { course_id: 20, intern_ids: [9001] });
  assert.equal(second.status, 200);
  assert.equal(assignmentInsertCount, 1);
  assert.equal(assignmentUpdateCount, 1);
});

test('course assignment rejects interns outside the team or department', async () => {
  teamAssignmentAllowed = false;
  assert.equal((await post('/assign-course', { course_id: 20, intern_ids: [9001] })).status, 403);
  teamAssignmentAllowed = true;
  internDepartmentId = 2;
  assert.equal((await post('/assign-course', { course_id: 20, intern_ids: [9001] })).status, 400);
  assert.equal(assignmentInsertCount, 0);
});

test('locked init is denied without SQL mutations', async () => {
  const response = await post('/init', { video_id: 2 });
  assert.equal(response.status, 403);
  assert.equal(response.body.required_video_id, 1);
  assert.equal(queries.some((q) => /^(INSERT|UPDATE)/.test(q.sql)), false);
});

test('cross-department and unpublished videos cannot initialize', async () => {
  departmentAllowed = false;
  assert.equal((await post('/init', { video_id: 1 })).status, 404);
  departmentAllowed = true;
  published = false;
  assert.equal((await post('/init', { video_id: 1 })).status, 404);
  assert.equal(queries.some((q) => /^(INSERT|UPDATE)/.test(q.sql)), false);
});

test('session init returns authorized stream and completed rewatch remains complete', async () => {
  complete(1);
  const response = await post('/init', { video_id: 1 });
  assert.equal(response.status, 200);
  assert.equal(response.body.is_completed, true);
  assert.match(response.body.media_url, /^\/api\/v1\/intern\/video\/1\/stream\?session_token=[a-f0-9]{64}$/);
  assert.equal(response.body.session_token, logs.get(1).session_token);
  assert.equal(logs.get(1).watch_count, 2);
});

test('incomplete legacy session cannot credit a locked lesson', async () => {
  const token = crypto.randomBytes(32).toString('hex');
  logs.set(2, { id: 2, session_token: token });
  const response = await post('/heartbeat', { video_id: 2, session_token: token, current_position_seconds: 5 });
  assert.equal(response.status, 403);
  assert.equal(queries.some((q) => /^(INSERT|UPDATE)/.test(q.sql)), false);
});

test('validated watch completion unlocks next lesson and cannot regress on rewatch', async () => {
  const { body } = await post('/init', { video_id: 1 });
  logs.get(1).last_heartbeat_at = new Date(Date.now() - 7000);
  const first = await post('/heartbeat', { video_id: 1, session_token: body.session_token, current_position_seconds: 7, tab_active: true });
  assert.equal(first.body.is_completed, false);
  assert.equal((await getVideoAccess(9001, 2)).is_unlocked, false);
  logs.get(1).last_heartbeat_at = new Date(Date.now() - 3000);
  const second = await post('/heartbeat', { video_id: 1, session_token: body.session_token, current_position_seconds: 10, tab_active: true });
  assert.equal(second.body.is_completed, true);
  assert.equal((await getVideoAccess(9001, 2)).is_unlocked, true);
  assert.equal((await getVideoAccess(9001, 3)).is_unlocked, false);
  const rewatch = await post('/heartbeat', { video_id: 1, session_token: body.session_token, current_position_seconds: 0, tab_active: false });
  assert.equal(rewatch.body.is_completed, true);
});

test('inactive tab and unchanged media position earn no watch credit', async () => {
  const { body } = await post('/init', { video_id: 1 });
  logs.get(1).last_heartbeat_at = new Date(Date.now() - 7000);
  assert.equal((await post('/heartbeat', { video_id: 1, session_token: body.session_token, current_position_seconds: 7, tab_active: false })).body.accumulated_delta, 0);
  logs.get(1).last_heartbeat_at = new Date(Date.now() - 7000);
  assert.equal((await post('/heartbeat', { video_id: 1, session_token: body.session_token, current_position_seconds: 7, tab_active: true })).body.accumulated_delta, 0);
});

test('invalid IDs and malformed heartbeat values are rejected', async () => {
  assert.equal((await post('/init', { video_id: 'bad' })).status, 400);
  assert.equal((await post('/init', { video_id: -1 })).status, 400);
  for (const patch of [{ current_position_seconds: -2 }, { current_position_seconds: 'bad' }, { playback_speed: 9 }, { tab_active: 'true' }]) {
    assert.equal((await post('/heartbeat', { video_id: 1, session_token: crypto.randomBytes(32).toString('hex'), current_position_seconds: 3, ...patch })).status, 400);
  }
});

test('old, disabled, missing, and wrong-video sessions cannot stream', async () => {
  complete(1);
  const token = logs.get(1).session_token;
  assert.equal((await fetch(`${base}/stream/1`)).status, 403);
  assert.equal((await fetch(`${base}/stream/2?session_token=${token}`)).status, 403);
  activeUser = false;
  assert.equal((await fetch(`${base}/stream/1?session_token=${token}`)).status, 403);
  activeUser = true;
  sessionFresh = false;
  assert.equal((await fetch(`${base}/stream/1?session_token=${token}`)).status, 403);
});

test('locked stream rejects an existing legacy session', async () => {
  logs.set(2, { id: 2, session_token: crypto.randomBytes(32).toString('hex'), is_completed: 0 });
  assert.equal((await fetch(`${base}/stream/2?session_token=${logs.get(2).session_token}`)).status, 403);
});

test('authorized uploaded media supports byte ranges and HEAD with no public cache', async () => {
  await fs.mkdir(path.join(sandbox, 'uploads', 'videos'), { recursive: true });
  await fs.writeFile(path.join(sandbox, 'uploads', 'videos', 'lesson1.mp4'), Buffer.from('isolated-media-fixture'));
  complete(1);
  const url = `${base}/stream/1?session_token=${logs.get(1).session_token}`;
  const response = await fetch(url, { headers: { Range: 'bytes=0-7' } });
  assert.equal(response.status, 206);
  assert.equal(await response.text(), 'isolated');
  assert.match(response.headers.get('cache-control'), /private, no-store/);
  assert.match(response.headers.get('content-range'), /^bytes 0-7\//);
  const head = await fetch(url, { method: 'HEAD' });
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
});

test('raw uploaded media is private, including encoded and uppercase file paths', async () => {
  for (const route of ['/uploads/videos/lesson1.mp4', '/uploads/old.MP4', '/uploads/old%2Emp4', '/uploads/videos/lesson.mkv']) {
    assert.equal((await fetch(`${base}${route}`)).status, 401);
  }
  assert.equal((await fetch(`${base}/uploads/unknown.pdf`)).status, 404);
  assert.equal(isVideoUploadPath('/images/logo.png'), false);
  assert.equal(isVideoUploadPath('/videos/no-extension'), true);
});

test('Windows dot-segment, trailing-dot and NTFS stream aliases cannot expose raw media', async () => {
  assert.equal((await fetch(`${base}/uploads/%2e/videos/lesson1.mp4`)).status, 401);
  for (const route of ['/uploads/%2e/videos/lesson1.mp4::$DATA', '/uploads/old.mp4%3A%3A%24DATA', '/uploads/old.mp4.', '/uploads/old.mp4%20']) {
    assert.equal((await fetch(`${base}${route}`)).status, 400);
  }
  assert.equal(isVideoUploadPath('/./videos/no-extension'), true);
});

test('overlapping stale heartbeats cannot revoke completion or reduce watch totals', async () => {
  const { body } = await post('/init', { video_id: 1 });
  Object.assign(logs.get(1), { last_position_seconds: 8, total_watched_seconds: 8, completion_percentage: 80, last_heartbeat_at: new Date(Date.now() - 3000) });
  const query = pool.query;
  let reads = 0;
  let release;
  const ready = new Promise((resolve) => { release = resolve; });
  pool.query = async (sql, values) => {
    if (sql.startsWith('SELECT * FROM video_watch_logs') && ++reads <= 2) {
      const snapshot = await query(sql, values);
      if (reads === 2) release();
      await ready;
      return snapshot;
    }
    if (sql.includes('UPDATE video_watch_logs') && values[1] === 8) {
      await new Promise((resolve) => setTimeout(resolve, 30));
    }
    return query(sql, values);
  };
  const responses = await Promise.all([
    post('/heartbeat', { video_id: 1, session_token: body.session_token, current_position_seconds: 10, tab_active: true }),
    post('/heartbeat', { video_id: 1, session_token: body.session_token, current_position_seconds: 8, tab_active: false }),
  ]);
  assert.ok(responses.every((response) => response.status === 200 && response.body.is_completed));
  assert.equal(logs.get(1).is_completed, 1);
  assert.equal(logs.get(1).total_watched_seconds, 10);
  assert.equal((await getVideoAccess(9001, 2)).is_unlocked, true);
});

test('rotation of a session during a heartbeat prevents its stale mutation', async () => {
  const { body } = await post('/init', { video_id: 1 });
  const query = pool.query;
  pool.query = async (sql, values) => {
    if (sql.includes('UPDATE video_watch_logs')) logs.get(1).session_token = crypto.randomBytes(32).toString('hex');
    return query(sql, values);
  };
  const response = await post('/heartbeat', { video_id: 1, session_token: body.session_token, current_position_seconds: 10, tab_active: true });
  assert.equal(response.status, 403);
  assert.equal(logs.get(1).total_watched_seconds, 0);
});

test('upload resolver prevents traversal outside upload directory', () => {
  assert.equal(resolveVideoUploadPath('https://example.invalid/video.mp4'), null);
  assert.equal(resolveVideoUploadPath('/uploads/videos/lesson.mp4'), path.join(sandbox, 'uploads', 'videos', 'lesson.mp4'));
  for (const source of ['/uploads/../private-file', '/uploads/%2e%2e/private-file', '/uploads/%2e%2e%5cprivate-file']) {
    assert.throws(() => resolveVideoUploadPath(source));
  }
});
