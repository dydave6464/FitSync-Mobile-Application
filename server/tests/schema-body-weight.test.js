'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

// A characterization test, not a new-feature test. body_weight_logs has
// existed unused since 005_activity_motivation.sql; the body weight endpoints
// are about to depend on its exact column names, so pin them here rather than
// discover a rename through a failing query three tasks later.
test('body_weight_logs shape', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [cols] = await pool.query(
    `SELECT column_name AS name, is_nullable AS nullable, data_type AS type
       FROM information_schema.columns
      WHERE table_schema = ? AND table_name = 'body_weight_logs'`,
    [testDbConfig().database],
  );
  const byName = Object.fromEntries(cols.map((c) => [c.name, c]));

  assert.ok(byName.weight_log_id, 'weight_log_id is the primary key column');
  assert.equal(byName.weight_kg.type, 'decimal');
  assert.equal(byName.weight_kg.nullable, 'NO');
  assert.ok(byName.log_date, 'the date column is log_date, not logged_on');
  assert.equal(byName.log_date.type, 'date');

  // No unique key on (user_id, log_date) -- which is why one-entry-per-day is
  // enforced in db/body-weight.js rather than by the schema.
  const [idx] = await pool.query(
    `SELECT index_name AS name, non_unique AS dup
       FROM information_schema.statistics
      WHERE table_schema = ? AND table_name = 'body_weight_logs'
        AND non_unique = 0 AND index_name <> 'PRIMARY'`,
    [testDbConfig().database],
  );
  assert.equal(idx.length, 0, 'no unique constraint beyond the primary key');
});
