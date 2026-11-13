'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('usual rice schema (049)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('users gains usual_rice_cups: 1 cup unless chosen', async () => {
    const [rows] = await pool.query("SHOW COLUMNS FROM users LIKE 'usual_rice_cups'");
    assert.deepEqual(rows.map((r) => [r.Type, r.Null, r.Default]), [['decimal(2,1)', 'NO', '1.0']]);
  });
});
