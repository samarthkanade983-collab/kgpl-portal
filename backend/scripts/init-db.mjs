// Loads schema + demo seed on first boot (when the `users` table is missing).
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import mysql from 'mysql2/promise';

const url = process.env.MYSQL_URL || process.env.DATABASE_URL;
if (!url) {
  console.log('init-db: no MYSQL_URL/DATABASE_URL, skipping');
  process.exit(0);
}
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'db');
const conn = await mysql.createConnection({ uri: url, multipleStatements: true });
const [rows] = await conn.query("SHOW TABLES LIKE 'users'");
if (rows.length === 0) {
  console.log('init-db: empty database, loading schema and seed');
  await conn.query(fs.readFileSync(path.join(dir, 'schema.sql'), 'utf8'));
  await conn.query(fs.readFileSync(path.join(dir, 'seed.sql'), 'utf8'));
  console.log('init-db: done');
} else {
  console.log('init-db: schema present, skipping');
}
await conn.end();
