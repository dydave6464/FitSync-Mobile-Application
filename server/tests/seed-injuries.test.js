'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries, REGIONS } = require('../src/db/seed-injuries');

test('injury seed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('seeds all sixteen regions', async () => {
    const summary = await seedInjuries(testDbConfig());
    assert.equal(summary.inserted, 16);
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM injuries');
    assert.equal(rows[0].n, 16);
  });

  await t.test('is idempotent', async () => {
    await seedInjuries(testDbConfig());
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM injuries');
    assert.equal(rows[0].n, 16, 'a second run must not duplicate rows');
  });

  await t.test('back and core regions are not lateral', async () => {
    const [rows] = await pool.query(
      "SELECT name FROM injuries WHERE is_lateral = FALSE ORDER BY name",
    );
    assert.deepEqual(rows.map((r) => r.name), ['Core', 'Lower back', 'Neck', 'Upper back']);
  });

  await t.test('every region has one of three groups', async () => {
    const groups = new Set(REGIONS.map((r) => r.regionGroup));
    assert.deepEqual([...groups].sort(), ['back_core', 'lower_body', 'upper_body']);
  });
});
