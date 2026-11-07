'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('food hiding schema (045)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('foods.hidden_at is a nullable timestamp that defaults to NULL', async () => {
    const [rows] = await pool.query("SHOW COLUMNS FROM foods LIKE 'hidden_at'");
    assert.equal(rows.length, 1);
    assert.equal(rows[0].Type, 'timestamp');
    assert.equal(rows[0].Null, 'YES');
    assert.equal(rows[0].Default, null);
  });

  await t.test('a new food is shown', async () => {
    const [f] = await pool.query("INSERT INTO foods (name, calories) VALUES ('Taho', 150)");
    const [[row]] = await pool.query('SELECT hidden_at FROM foods WHERE food_id = ?', [f.insertId]);
    assert.equal(row.hidden_at, null);
  });
});
