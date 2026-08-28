'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');

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

  // seedInjuries used to return { inserted: 16 } unconditionally, even when
  // every row already existed and nothing actually changed. Now that a human
  // reads this number off a console (scripts/seed-injuries.js), it must
  // report what really happened on this run, not a constant.
  await t.test('reports zero inserted on a pure-update run', async () => {
    const summary = await seedInjuries(testDbConfig());
    assert.equal(summary.inserted, 0, 'nothing was newly inserted this run');
    assert.equal(summary.unchanged, 16, 'every row already matched exactly');
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM injuries');
    assert.equal(rows[0].n, 16);
  });

  await t.test('back and core regions are not lateral', async () => {
    const [rows] = await pool.query(
      "SELECT name FROM injuries WHERE is_lateral = FALSE ORDER BY name",
    );
    assert.deepEqual(rows.map((r) => r.name), ['Core', 'Lower back', 'Neck', 'Upper back']);
  });

  await t.test('every region has one of three groups', async () => {
    // Reading REGIONS instead of querying the database would still pass even
    // if the seed wrote nothing at all, or wrote the wrong region_group
    // values — it only pins the JS constant against itself. Querying
    // injuries.region_group is what actually proves the seed wrote what
    // REGIONS says it should have.
    const [rows] = await pool.query('SELECT DISTINCT region_group FROM injuries');
    assert.deepEqual(
      rows.map((r) => r.region_group).sort(),
      ['back_core', 'lower_body', 'upper_body'],
    );
    // Every one of the 16 rows must carry one of those three groups — not
    // just that the three values appear somewhere.
    const [countRows] = await pool.query(
      "SELECT COUNT(*) AS n FROM injuries WHERE region_group NOT IN ('back_core', 'lower_body', 'upper_body')",
    );
    assert.equal(countRows[0].n, 0, 'every row must have one of the three known groups');
  });
});
