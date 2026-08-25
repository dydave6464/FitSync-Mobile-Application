'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const mysql = require('mysql2/promise');

const DEFAULT_MIGRATIONS_DIR = path.join(__dirname, 'migrations');

const SCHEMA_MIGRATIONS = `
  CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) NOT NULL PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
`;

async function migrate(dbConfig, { migrationsDir = DEFAULT_MIGRATIONS_DIR, logger = null } = {}) {
  const connection = await mysql.createConnection({
    host: dbConfig.host,
    port: dbConfig.port,
    user: dbConfig.user,
    password: dbConfig.password,
    database: dbConfig.database,
    multipleStatements: true,
    charset: 'utf8mb4',
  });

  const applied = [];

  try {
    await connection.query(SCHEMA_MIGRATIONS);

    const [rows] = await connection.query('SELECT version FROM schema_migrations');
    const done = new Set(rows.map((row) => row.version));

    const entries = await fs.readdir(migrationsDir);
    const files = entries.filter((name) => name.endsWith('.sql')).sort();

    for (const file of files) {
      if (done.has(file)) continue;

      const sql = await fs.readFile(path.join(migrationsDir, file), 'utf8');
      try {
        await connection.query(sql);
        await connection.query('INSERT INTO schema_migrations (version) VALUES (?)', [file]);
      } catch (err) {
        throw new Error(`Migration ${file} failed: ${err.message}`);
      }

      applied.push(file);
      if (logger && logger.info) logger.info(`applied migration ${file}`);
    }
  } finally {
    await connection.end();
  }

  return applied;
}

module.exports = { migrate, DEFAULT_MIGRATIONS_DIR };
