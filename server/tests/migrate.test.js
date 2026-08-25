'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { migrate } = require('../src/db/migrate');
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
