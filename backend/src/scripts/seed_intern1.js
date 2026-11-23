import mysql from 'mysql2/promise';
import bcrypt from 'bcryptjs';

async function seed() {
  const conn = await mysql.createConnection({
    host: '127.0.0.1',
    user: 'root',
    password: '',
    database: 'kgpl_portal'
  });

  const hash = await bcrypt.hash('Password@123', 10);

  const [existing] = await conn.execute('SELECT id FROM users WHERE email = ?', ['intern1@kgpl.com']);
  if (existing.length === 0) {
    const [res] = await conn.execute(
      'INSERT INTO users (name, email, password, role, is_active, created_at, updated_at) VALUES (?, ?, ?, ?, 1, NOW(), NOW())',
      ['David Miller (Intern 1)', 'intern1@kgpl.com', hash, 'intern']
    );
    const userId = res.insertId;
    await conn.execute(
      'INSERT INTO intern_profiles (user_id, department_id, batch_id, intern_code, internship_start_date, status, created_at, updated_at) VALUES (?, 1, 1, ?, NOW(), "active", NOW(), NOW())',
      [userId, 'INT-001']
    );
    console.log('Created intern1@kgpl.com with ID:', userId);
  } else {
    await conn.execute('UPDATE users SET password = ?, is_active = 1 WHERE email = ?', [hash, 'intern1@kgpl.com']);
    console.log('Updated intern1 password');
  }

  // Update all standard accounts to also have bcrypt hash of Password@123
  await conn.execute(
    'UPDATE users SET password = ?, is_active = 1 WHERE email IN ("intern@kgpl.com", "tl@kgpl.com", "hr@kgpl.com")',
    [hash]
  );
  console.log('Updated all users to accept Password@123 and specialized passwords!');

  await conn.end();
}

seed().catch(console.error);
