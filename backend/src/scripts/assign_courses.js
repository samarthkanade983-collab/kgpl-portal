import mysql from 'mysql2/promise';

async function assignCourse() {
  const conn = await mysql.createConnection({
    host: '127.0.0.1',
    user: 'root',
    password: '',
    database: 'kgpl_portal'
  });

  // Check if course 2 is assigned
  const [existing] = await conn.execute('SELECT * FROM course_assignments WHERE course_id = 2');
  if (existing.length === 0) {
    await conn.execute(
      'INSERT INTO course_assignments (course_id, assigned_by, user_id, batch_id, assigned_at, due_date, created_at, updated_at) VALUES (2, 1, NULL, 1, NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY), NOW(), NOW())'
    );
    console.log('Assigned Course 2 (It Infra) to Batch 1');
  } else {
    console.log('Course 2 is already assigned');
  }

  // Also verify Course 3
  const [c3] = await conn.execute('SELECT * FROM course_assignments WHERE course_id = 3');
  if (c3.length === 0) {
    await conn.execute(
      'INSERT INTO course_assignments (course_id, assigned_by, user_id, batch_id, assigned_at, due_date, created_at, updated_at) VALUES (3, 1, NULL, 1, NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY), NOW(), NOW())'
    );
    console.log('Assigned Course 3 to Batch 1');
  }

  await conn.end();
}

assignCourse().catch(console.error);
