'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('user suspension schema (044)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('users.suspended_at is a nullable timestamp that defaults to NULL', async () => {
    const [rows] = await pool.query("SHOW COLUMNS FROM users LIKE 'suspended_at'");
    assert.equal(rows.length, 1);
    assert.equal(rows[0].Type, 'timestamp');
    assert.equal(rows[0].Null, 'YES');
    assert.equal(rows[0].Default, null);
  });

  await t.test('a new user is not suspended', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('active@b.com', 'x', 'A')",
    );
    const [[row]] = await pool.query('SELECT suspended_at FROM users WHERE user_id = ?', [u.insertId]);
    assert.equal(row.suspended_at, null);
  });
});
