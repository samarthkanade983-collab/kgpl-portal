import { test, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

const { pool } = await import('../src/config/db.ts');
const { createCourse } = await import('../src/controllers/hr.controller.ts');
const originalQuery = pool.query;
const queries = [];
let duplicateCourse;
let slugCollisions;
let insertedSlugs;

const app = express();
app.use(express.json());
app.post('/courses', (req, res, next) => {
  req.user = { id: 80, role: 'team_leader' };
  next();
}, createCourse);
const server = app.listen(0, '127.0.0.1');
await new Promise((resolve) => server.on('listening', resolve));
const base = `http://127.0.0.1:${server.address().port}`;

beforeEach(() => {
  queries.length = 0;
  duplicateCourse = null;
  slugCollisions = new Set();
  insertedSlugs = [];
  pool.query = async (sql, values = []) => {
    queries.push({ sql, values });
    if (sql.includes('LOWER(TRIM(title))')) {
      return [duplicateCourse ? [duplicateCourse] : [], []];
    }
    if (sql.startsWith('INSERT INTO courses')) {
      const slug = values[1];
      insertedSlugs.push(slug);
      if (slugCollisions.has(slug)) {
        const error = new Error(`Duplicate slug: ${slug}`);
        error.code = 'ER_DUP_ENTRY';
        throw error;
      }
      return [{ insertId: 121 }, []];
    }
    if (sql.startsWith('INSERT INTO audit_logs')) return [{ affectedRows: 1 }, []];
    throw new Error(`Unexpected query: ${sql}`);
  };
});

after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
  pool.query = originalQuery;
  await pool.end();
});

async function postCourse(body) {
  return fetch(`${base}/courses`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

test('duplicate course in the same department returns an actionable conflict', async () => {
  duplicateCourse = { id: 17, title: 'It infra' };
  const response = await postCourse({
    title: 'IT Infra',
    department_id: 11,
    is_published: 1,
  });
  assert.equal(response.status, 409);
  const payload = await response.json();
  assert.equal(payload.course_id, 17);
  assert.match(payload.error, /Use the existing course/);
  assert.equal(insertedSlugs.length, 0);
});

test('slug collisions across departments get a unique slug instead of failing', async () => {
  slugCollisions.add('it-infra');
  const response = await postCourse({
    title: 'It infra',
    department_id: 12,
    is_published: 1,
  });
  assert.equal(response.status, 201);
  assert.deepEqual(insertedSlugs, ['it-infra', 'it-infra-2']);
  assert.equal((await response.json()).course_id, 121);
});
