import mysql from 'mysql2/promise';

const poolConfig: mysql.PoolOptions = (process.env.MYSQL_URL || process.env.DATABASE_URL)
  ? {
      uri: process.env.MYSQL_URL || process.env.DATABASE_URL,
      waitForConnections: true,
      connectionLimit: 20,
      queueLimit: 0,
      enableKeepAlive: true,
      keepAliveInitialDelay: 10000,
    }
  : {
      host: process.env.DB_HOST || '127.0.0.1',
      port: Number(process.env.DB_PORT) || 3306,
      user: process.env.DB_USER || 'root',
      password: process.env.DB_PASSWORD || '',
      database: process.env.DB_NAME || 'kgpl_portal',
      waitForConnections: true,
      connectionLimit: 20,
      queueLimit: 0,
      enableKeepAlive: true,
      keepAliveInitialDelay: 10000,
    };

export const pool = mysql.createPool(poolConfig);

export async function testConnection(): Promise<void> {
  try {
    const [rows] = await pool.query('SELECT 1 + 1 AS result');
    console.log('✅ MySQL 8 Database Pool connected successfully. Ready for high-concurrency requests.');
  } catch (error) {
    console.error('❌ Failed to connect to MySQL database:', error);
    process.exit(1);
  }
}
