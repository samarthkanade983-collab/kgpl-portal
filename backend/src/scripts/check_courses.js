import mysql from 'mysql2/promise';

async function check() {
  const conn = await mysql.createConnection({
    host: '127.0.0.1',
    user: 'root',
    password: '',
    database: 'kgpl_portal'
  });

  const [courseModulesCols] = await conn.execute('DESCRIBE course_modules');
  console.log('course_modules columns:', courseModulesCols.map(c => c.Field));

  const [videosCols] = await conn.execute('DESCRIBE videos');
  console.log('videos columns:', videosCols.map(c => c.Field));

  const [modules] = await conn.execute('SELECT * FROM course_modules');
  console.log('course_modules data:', modules);

  const [videos] = await conn.execute('SELECT id, module_id, title, video_url, duration_seconds FROM videos');
  console.log('videos data:', videos);

  await conn.end();
}

check().catch(console.error);
