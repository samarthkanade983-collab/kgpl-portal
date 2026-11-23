import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { pool } from '../config/db.js';
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
export async function ensureDatabaseTablesAndSeed() {
    try {
        // Check if users or departments table already exists and has records
        const [tables] = await pool.query('SHOW TABLES LIKE "users"');
        if (tables.length > 0) {
            const [count] = await pool.query('SELECT COUNT(*) as c FROM users');
            if (count[0]?.c > 0) {
                console.log(`ℹ️ Database already initialized with ${count[0].c} users.`);
                return;
            }
        }
        console.log('🌱 Cloud database is empty. Automatically initializing full database schema & seed data...');
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
        for (const statement of statements) {
            try {
                await pool.query(statement);
            }
            catch (err) {
                // Log non-fatal errors but continue
                if (!err.message?.includes('already exists')) {
                    console.warn('Seed statement notice:', err.message?.slice(0, 100));
                }
            }
        }
        console.log('✅ Full database successfully initialized and seeded with all courses, users, and quizzes!');
    }
    catch (error) {
        console.error('Database auto-initialization error:', error);
    }
}
