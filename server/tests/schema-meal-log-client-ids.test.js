'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

async function columns(pool, table) {
  const [rows] = await pool.query(
    `SELECT COLUMN_NAME AS name, COLUMN_TYPE AS type, IS_NULLABLE AS nullable, COLUMN_KEY AS ckey
       FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION`,
    [table],
  );
  return Object.fromEntries(rows.map((r) => [r.name, r]));
}

test('meal log client id schema (043)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const count = async (where, params) => Number((await pool.query(
    `SELECT COUNT(*) AS n FROM meal_log_client_ids WHERE ${where}`, params,
  ))[0][0].n);
  const user = async (email) => (await pool.query(
    'INSERT INTO users (email, password_hash, full_name) VALUES (?, ?, ?)', [email, 'x', 'U'],
  ))[0].insertId;
  const entry = async (userId) => (await pool.query(
    "INSERT INTO meal_logs (user_id, custom_name, meal_type, servings, calories, logged_via, log_date) VALUES (?, 'Rice', 'lunch', 1, 200, 'manual', CURDATE())",
    [userId],
  ))[0].insertId;

  await t.test('meal_log_client_ids: one key per user and client id, one per entry', async () => {
    const c = await columns(pool, 'meal_log_client_ids');
    assert.deepEqual(Object.keys(c), ['user_id', 'client_id', 'meal_log_id', 'created_at']);
    assert.equal(c.client_id.type, 'char(36)');
    assert.ok(Object.values(c).every((col) => col.nullable === 'NO'));
    const [pk] = await pool.query(
      `SELECT COLUMN_NAME AS name FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meal_log_client_ids' AND CONSTRAINT_NAME = 'PRIMARY'
        ORDER BY ORDINAL_POSITION`,
    );
    assert.deepEqual(pk.map((r) => r.name), ['user_id', 'client_id']);

    const u = await user('key@b.com');
    const id = await entry(u);
    await pool.query("INSERT INTO meal_log_client_ids (user_id, client_id, meal_log_id) VALUES (?, 'a', ?)", [u, id]);
    await assert.rejects(
      pool.query("INSERT INTO meal_log_client_ids (user_id, client_id, meal_log_id) VALUES (?, 'b', ?)", [u, id]),
      { code: 'ER_DUP_ENTRY' }, 'an entry has at most one key',
    );
  });

  await t.test('deleting the entry deletes its key', async () => {
    const u = await user('entry@b.com');
    const id = await entry(u);
    await pool.query("INSERT INTO meal_log_client_ids (user_id, client_id, meal_log_id) VALUES (?, 'c', ?)", [u, id]);
    await pool.query('DELETE FROM meal_logs WHERE meal_log_id = ?', [id]);
    assert.equal(await count('meal_log_id = ?', [id]), 0);
  });

  await t.test('deleting the user deletes their keys', async () => {
    const u = await user('gone@b.com');
    const id = await entry(u);
    await pool.query("INSERT INTO meal_log_client_ids (user_id, client_id, meal_log_id) VALUES (?, 'd', ?)", [u, id]);
    await pool.query('DELETE FROM users WHERE user_id = ?', [u]);
    assert.equal(await count('user_id = ?', [u]), 0);
  });
});
