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

/// Which migration files this database has not applied yet.
///
/// Read-only, deliberately: it must not create `schema_migrations` the way
/// [migrate] does, or the first boot against an empty database would report
/// nothing pending on its second attempt. A missing table therefore means
/// "none applied" rather than an error.
///
/// Exists because a database silently behind on migrations does not announce
/// itself -- it surfaces much later as a 500 from whichever endpoint touches
/// the missing table first, under a message that names neither the table nor
/// the migration.
async function pendingMigrations(
  dbConfig,
  { migrationsDir = DEFAULT_MIGRATIONS_DIR } = {},
) {
  const connection = await mysql.createConnection({
    host: dbConfig.host,
    port: dbConfig.port,
    user: dbConfig.user,
    password: dbConfig.password,
    database: dbConfig.database,
    charset: 'utf8mb4',
  });

  try {
    let done = new Set();
    try {
      const [rows] = await connection.query('SELECT version FROM schema_migrations');
      done = new Set(rows.map((row) => row.version));
    } catch (err) {
      // Anything other than "the table isn't there yet" is a real problem --
      // a permission error read as "nothing applied" would tell the operator
      // to run migrations that will fail the same way.
      if (err.code !== 'ER_NO_SUCH_TABLE') throw err;
    }

    const entries = await fs.readdir(migrationsDir);
    return entries
      .filter((name) => name.endsWith('.sql'))
      .sort()
      .filter((name) => !done.has(name));
  } finally {
    await connection.end();
  }
}

/// Refuses to continue when the database is behind the migrations on disk.
///
/// Called at boot, in the same spirit as the config guards in
/// `src/config/index.js`: fail at startup, not in an incident. A database one
/// migration behind serves most of the app perfectly and then answers a single
/// endpoint with a 500 that names nothing -- which is exactly how
/// 015_session_exercises.sql went unnoticed. The cost of being wrong here is a
/// server that will not boot until someone runs one command; the cost of not
/// checking is a bug report.
async function assertSchemaCurrent(dbConfig, options = {}) {
  const pending = await pendingMigrations(dbConfig, options);
  if (pending.length === 0) return;

  throw new Error(
    `Database "${dbConfig.database}" is behind on ${pending.length} `
      + `migration${pending.length === 1 ? '' : 's'}: ${pending.join(', ')}. `
      + 'Run `npm run migrate` before starting the server.',
  );
}

module.exports = {
  migrate, pendingMigrations, assertSchemaCurrent, DEFAULT_MIGRATIONS_DIR,
};
