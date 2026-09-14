'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {
  migrate, pendingMigrations, assertSchemaCurrent,
} = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables, tableNames } = require('./helpers/test-db');

const FIXTURES = path.join(__dirname, 'fixtures', 'migrations');

test('migration runner', async (t) => {
  const pool = createPool(testDbConfig());
  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('applies pending migrations to an empty database', async () => {
    await dropAllTables(pool);
    const applied = await migrate(testDbConfig(), { migrationsDir: FIXTURES });
    assert.deepEqual(applied, ['001_fixture.sql']);

    const names = await tableNames(pool);
    assert.ok(names.includes('fixture_widgets'));
    assert.ok(names.includes('fixture_gadgets'));
  });

  await t.test('records applied versions in schema_migrations', async () => {
    const [rows] = await pool.query('SELECT version FROM schema_migrations ORDER BY version');
    assert.deepEqual(rows.map((r) => r.version), ['001_fixture.sql']);
  });

  await t.test('is idempotent — a second run applies nothing', async () => {
    const applied = await migrate(testDbConfig(), { migrationsDir: FIXTURES });
    assert.deepEqual(applied, []);
  });

  await t.test('creates foreign keys that actually enforce', async () => {
    await assert.rejects(
      () => pool.query('INSERT INTO fixture_gadgets (widget_id) VALUES (99999)'),
      (err) => err.code === 'ER_NO_REFERENCED_ROW_2' || err.code === 'ER_NO_REFERENCED_ROW',
    );
  });

  await t.test('reports nothing pending once every migration is applied',
    async () => {
      assert.deepEqual(
        await pendingMigrations(testDbConfig(), { migrationsDir: FIXTURES }),
        [],
      );
    });

  await t.test('names the migrations a database is behind on', async () => {
    // The failure this exists to prevent: 015_session_exercises.sql sat
    // unapplied on a developer database, and the first anyone heard of it was
    // a 500 from POST /sessions reading 'An unexpected error occurred.' The
    // table was missing, so every session read threw ER_NO_SUCH_TABLE.
    const fs = require('node:fs');
    const dir = path.join(__dirname, 'fixtures', 'pending-migrations');
    fs.mkdirSync(dir, { recursive: true });
    fs.copyFileSync(
      path.join(FIXTURES, '001_fixture.sql'),
      path.join(dir, '001_fixture.sql'),
    );
    fs.writeFileSync(
      path.join(dir, '002_later.sql'),
      'CREATE TABLE IF NOT EXISTS fixture_later (id INT PRIMARY KEY);',
    );

    try {
      // 001 is already applied from the tests above; 002 is not.
      assert.deepEqual(
        await pendingMigrations(testDbConfig(), { migrationsDir: dir }),
        ['002_later.sql'],
      );
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  await t.test('treats a database with no schema_migrations as fully behind',
    async () => {
      // A brand-new database has no schema_migrations table at all. Reading
      // that as "nothing pending" would let the server boot onto an empty
      // schema, which is the same failure with every table missing rather
      // than one.
      await dropAllTables(pool);
      assert.deepEqual(
        await pendingMigrations(testDbConfig(), { migrationsDir: FIXTURES }),
        ['001_fixture.sql'],
      );
      // Left applied so the ordering of later subtests does not depend on
      // this one having run.
      await migrate(testDbConfig(), { migrationsDir: FIXTURES });
    });

  await t.test('does not create schema_migrations as a side effect of asking',
    async () => {
      // A read must stay a read: a check that created the table would make
      // the very first boot against an empty database report "nothing
      // pending" on its second attempt.
      await dropAllTables(pool);
      await pendingMigrations(testDbConfig(), { migrationsDir: FIXTURES });

      const names = await tableNames(pool);
      assert.ok(!names.includes('schema_migrations'),
        'pendingMigrations must not write to the database');

      await migrate(testDbConfig(), { migrationsDir: FIXTURES });
    });

  await t.test('the boot guard passes on a fully migrated database', async () => {
    await assertSchemaCurrent(testDbConfig(), { migrationsDir: FIXTURES });
  });

  await t.test('the boot guard refuses, naming the files and the fix',
    async () => {
      // The whole value of failing at boot is the message: an operator who
      // only learns "an unexpected error occurred" three screens into the app
      // has to go find what is missing. This one has to say what to run.
      const fs = require('node:fs');
      const dir = path.join(__dirname, 'fixtures', 'guard-migrations');
      fs.mkdirSync(dir, { recursive: true });
      fs.copyFileSync(
        path.join(FIXTURES, '001_fixture.sql'),
        path.join(dir, '001_fixture.sql'),
      );
      fs.writeFileSync(
        path.join(dir, '015_session_exercises.sql'),
        'CREATE TABLE IF NOT EXISTS fixture_guard (id INT PRIMARY KEY);',
      );

      try {
        await assert.rejects(
          () => assertSchemaCurrent(testDbConfig(), { migrationsDir: dir }),
          (err) => {
            assert.match(err.message, /015_session_exercises\.sql/,
              'the message must name what is missing');
            assert.match(err.message, /npm run migrate/,
              'the message must name the fix');
            return true;
          },
        );
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    });

  await t.test('reports the filename when a migration fails', async () => {
    const bad = path.join(__dirname, 'fixtures', 'bad-migrations');
    const fs = require('node:fs');
    fs.mkdirSync(bad, { recursive: true });
    fs.writeFileSync(path.join(bad, '001_broken.sql'), 'CREATE TABLE ;;;');
    await assert.rejects(
      () => migrate(testDbConfig(), { migrationsDir: bad }),
      /001_broken\.sql/,
    );
    fs.rmSync(bad, { recursive: true, force: true });
  });
});
