import mysql from 'mysql2/promise';
import bcrypt from 'bcryptjs';

async function resetUsers() {
  console.log('--- RESETTING USER DATA & PROVISIONING CLEAN ACCOUNTS ---');

  const conn = await mysql.createConnection({
    host: '127.0.0.1',
    user: 'root',
    password: '',
    database: 'kgpl_portal'
  });

  // Temporarily disable foreign keys to cleanly wipe user data
  await conn.execute('SET FOREIGN_KEY_CHECKS = 0');
  await conn.execute('TRUNCATE TABLE quiz_attempts');
  await conn.execute('TRUNCATE TABLE task_submissions');
  await conn.execute('TRUNCATE TABLE learning_progress');
  await conn.execute('TRUNCATE TABLE attendance');
  await conn.execute('TRUNCATE TABLE intern_profiles');
  await conn.execute('TRUNCATE TABLE users');
  await conn.execute('SET FOREIGN_KEY_CHECKS = 1');

  console.log('Cleared all prior user tables cleanly.');

  // Hash clean passwords
  const adminHash = await bcrypt.hash('Admin@123', 10);
  const leaderHash = await bcrypt.hash('Leader@123', 10);
  const internHash = await bcrypt.hash('Intern@123', 10);

  // 1. HR Admin
  const [hrRes] = await conn.execute(
    `INSERT INTO users (name, email, password, role, is_active, created_at, updated_at)
     VALUES ('Sarah Jenkins (HR Director)', 'hr@kgpl.com', ?, 'hr_admin', 1, NOW(), NOW())`,
    [adminHash]
  );
  console.log('Provisioned HR Admin (hr@kgpl.com / Admin@123), ID:', hrRes.insertId);

  // 2. Team Leader
  const [tlRes] = await conn.execute(
    `INSERT INTO users (name, email, password, role, is_active, created_at, updated_at)
     VALUES ('Alex Rivera (Tech Lead)', 'tl@kgpl.com', ?, 'team_leader', 1, NOW(), NOW())`,
    [leaderHash]
  );
  console.log('Provisioned Team Leader (tl@kgpl.com / Leader@123), ID:', tlRes.insertId);

  // 3. Intern 1
  const [intern1Res] = await conn.execute(
    `INSERT INTO users (name, email, password, role, is_active, created_at, updated_at)
     VALUES ('David Miller', 'intern@kgpl.com', ?, 'intern', 1, NOW(), NOW())`,
    [internHash]
  );
  console.log('Provisioned Intern 1 (intern@kgpl.com / Intern@123), ID:', intern1Res.insertId);

  // 4. Intern 2
  const [intern2Res] = await conn.execute(
    `INSERT INTO users (name, email, password, role, is_active, created_at, updated_at)
     VALUES ('Emma Watson', 'intern2@kgpl.com', ?, 'intern', 1, NOW(), NOW())`,
    [internHash]
  );
  console.log('Provisioned Intern 2 (intern2@kgpl.com / Intern@123), ID:', intern2Res.insertId);

  // Link Intern Profiles
  await conn.execute(
    `INSERT INTO intern_profiles (user_id, intern_code, department_id, batch_id, assigned_team_leader_id, internship_start_date, status, created_at, updated_at)
     VALUES 
     (?, 'KGPL-INT-001', 1, 1, ?, CURDATE(), 'active', NOW(), NOW()),
     (?, 'KGPL-INT-002', 1, 1, ?, CURDATE(), 'active', NOW(), NOW())`,
    [intern1Res.insertId, tlRes.insertId, intern2Res.insertId, tlRes.insertId]
  );
  console.log('Created intern profiles assigned to Team Leader Alex Rivera.');

  await conn.end();
  console.log('--- USER RESET COMPLETED SUCCESSFULLY ---');
}

resetUsers().catch(err => {
  console.error('Reset users error:', err);
  process.exit(1);
});
