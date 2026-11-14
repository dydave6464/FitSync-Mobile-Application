'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('food photo schema (053)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('foods gains photo_key: the stored photo key, NULL = none', async () => {
    const [rows] = await pool.query("SHOW COLUMNS FROM foods LIKE 'photo_key'");
    assert.deepEqual(rows.map((r) => [r.Type, r.Null, r.Default]), [['varchar(255)', 'YES', null]]);
  });
});
