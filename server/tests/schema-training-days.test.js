'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('user_training_days schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('td@example.com', 'x', 'T')",
  );
  const userId = u.insertId;

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('accepts weekdays 1 through 7', async () => {
    for (let weekday = 1; weekday <= 7; weekday += 1) {
      await pool.query(
        'INSERT INTO user_training_days (user_id, weekday) VALUES (?, ?)',
        [userId, weekday],
      );
    }
    const [rows] = await pool.query(
      'SELECT weekday FROM user_training_days WHERE user_id = ?', [userId],
    );
    assert.equal(rows.length, 7);
  });

  await t.test('refuses the same weekday twice for one user', async () => {
    await assert.rejects(
      () => pool.query(
        'INSERT INTO user_training_days (user_id, weekday) VALUES (?, 1)', [userId],
      ),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('refuses a weekday outside 1..7', async () => {
    // days_per_week has no CHECK and that is exactly what produced the
    // "1 of 0" tally the week strip has to special-case. This column does.
    for (const bad of [0, 8, -1]) {
      await assert.rejects(
        () => pool.query(
          'INSERT INTO user_training_days (user_id, weekday) VALUES (?, ?)',
          [userId, bad],
        ),
        (err) => err.code === 'ER_CHECK_CONSTRAINT_VIOLATED',
        `weekday ${bad} must be refused`,
      );
    }
  });

  await t.test('deleting the user takes their days with them', async () => {
    await pool.query('DELETE FROM users WHERE user_id = ?', [userId]);
    const [rows] = await pool.query(
      'SELECT weekday FROM user_training_days WHERE user_id = ?', [userId],
    );
    assert.equal(rows.length, 0);
  });
});
