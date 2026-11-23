import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { pool } from '../config/db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function ensureDatabaseTablesAndSeed(): Promise<void> {
  try {
    // Check if courses and quizzes are already populated
    let alreadyPopulated = false;
    try {
      const [courses]: any = await pool.query('SELECT COUNT(*) as c FROM courses');
      const [quizzes]: any = await pool.query('SELECT COUNT(*) as c FROM quizzes');
      if ((courses[0]?.c || 0) > 0 && (quizzes[0]?.c || 0) > 0) {
        alreadyPopulated = true;
      }
    } catch {
      alreadyPopulated = false;
    }

    if (alreadyPopulated && process.env.FORCE_RESTORE_DB !== 'true') {
      console.log('ℹ️ Database already initialized with full courses and quizzes.');
      return;
    }

    console.log('🌱 Restoring complete database dump with all courses, modules, videos, quizzes, and users...');
    const candidatePaths = [
      path.resolve(__dirname, '../../full_database_dump.sql'),
      path.resolve(__dirname, '../full_database_dump.sql'),
      path.resolve(process.cwd(), 'full_database_dump.sql'),
      path.resolve(process.cwd(), 'backend/full_database_dump.sql'),
    ];

    const dumpPath = candidatePaths.find((p) => fs.existsSync(p));
    if (!dumpPath) {
      console.warn('⚠️ full_database_dump.sql not found, skipping auto-seed.');
      return;
    }

    const sqlContent = fs.readFileSync(dumpPath, 'utf8');
    const statements = sqlContent
      .split(/;\r?\n/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0 && !s.startsWith('--'));

    try {
      await pool.query('SET FOREIGN_KEY_CHECKS = 0;');
    } catch (_) {}

    for (const statement of statements) {
      try {
        await pool.query(statement);
      } catch (err: any) {
        if (!err.message?.includes('already exists') && !err.message?.includes('Duplicate entry')) {
          console.warn('Seed statement notice:', err.message?.slice(0, 100));
        }
      }
    }

    try {
      await pool.query('SET FOREIGN_KEY_CHECKS = 1;');
    } catch (_) {}

    console.log('✅ Full database successfully initialized and seeded with all courses, users, videos, and quizzes!');
  } catch (error) {
    console.error('Database auto-initialization error:', error);
  }
}
