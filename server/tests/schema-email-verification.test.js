'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('email verification schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const columns = async (table) => {
    const [rows] = await pool.query(
      `SELECT column_name AS c, column_type AS t, is_nullable AS n, column_key AS k
         FROM information_schema.columns
        WHERE table_schema = ? AND table_name = ?`,
      [testDbConfig().database, table],
    );
    return Object.fromEntries(rows.map((r) => [r.c, r]));
  };

  await t.test('users gains email_verified, defaulting to unverified', async () => {
    const users = await columns('users');
    assert.ok(users.email_verified, 'email_verified column exists');
    assert.equal(users.email_verified.t, 'tinyint(1)');
    assert.equal(users.email_verified.n, 'NO');

    const [r] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name)
       VALUES ('fresh@example.com', 'x', 'Fresh')`,
    );
    const [rows] = await pool.query(
      'SELECT email_verified FROM users WHERE user_id = ?', [r.insertId],
    );
    assert.equal(rows[0].email_verified, 0, 'a new account starts unverified');
  });

  await t.test('auth_tokens has the shape both flows need', async () => {
    const tokens = await columns('auth_tokens');
    assert.equal(tokens.token_hash.k, 'PRI', 'the hash is the primary key');
    assert.equal(tokens.token_hash.t, 'char(64)', 'sized for a hex sha-256');
    assert.equal(
      tokens.purpose.t,
      "enum('verify_email','reset_password')",
      'one table serves both flows',
    );
    assert.equal(tokens.consumed_at.n, 'YES', 'null until spent');
    assert.equal(tokens.expires_at.n, 'NO');
  });

  await t.test('tokens die with their user', async () => {
    const [u] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name)
       VALUES ('cascade@example.com', 'x', 'Cascade')`,
    );
    await pool.query(
      `INSERT INTO auth_tokens (token_hash, user_id, purpose, expires_at)
       VALUES (REPEAT('a', 64), ?, 'verify_email', NOW())`, [u.insertId],
    );
    await pool.query('DELETE FROM users WHERE user_id = ?', [u.insertId]);
    const [left] = await pool.query(
      'SELECT 1 FROM auth_tokens WHERE user_id = ?', [u.insertId],
    );
    assert.equal(left.length, 0, 'ON DELETE CASCADE removed the token');
  });
});
