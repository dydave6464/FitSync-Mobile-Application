'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

async function columns(pool, table) {
  const [rows] = await pool.query(
    `SELECT COLUMN_NAME AS name, COLUMN_TYPE AS type, IS_NULLABLE AS nullable, COLUMN_DEFAULT AS dflt
       FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION`,
    [table],
  );
  return Object.fromEntries(rows.map((r) => [r.name, r]));
}

test('photo recognition schema (040)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('photo_recognitions: one row per photo the AI looked at', async () => {
    const c = await columns(pool, 'photo_recognitions');
    assert.deepEqual(Object.keys(c), ['recognition_id', 'user_id', 'created_at', 'item_count', 'status', 'logged_at']);
    assert.equal(c.status.type, "enum('recognised','empty','failed')");
    assert.equal(c.logged_at.nullable, 'YES');
  });

  await t.test('photo_recognition_items: what was suggested, and what became of it', async () => {
    const c = await columns(pool, 'photo_recognition_items');
    assert.deepEqual(Object.keys(c), [
      'item_id', 'recognition_id', 'item_order', 'suggested_food_id', 'suggested_name', 'confidence',
      'suggested_servings', 'alternative_food_ids', 'outcome', 'logged_food_id', 'meal_log_id',
    ]);
    assert.equal(c.outcome.type, "enum('pending','kept','swapped','removed')");
    assert.equal(c.outcome.dflt, 'pending');
    assert.equal(c.alternative_food_ids.type, 'json');
    assert.equal(c.suggested_food_id.nullable, 'YES');
    assert.equal(c.suggested_servings.nullable, 'YES');
  });

  // The photo is never kept: no column in either table could hold one.
  await t.test('no column could hold a photo', async () => {
    const [rows] = await pool.query(
      `SELECT TABLE_NAME AS t, COLUMN_NAME AS c FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('photo_recognitions', 'photo_recognition_items')
          AND (DATA_TYPE IN ('tinyblob', 'blob', 'mediumblob', 'longblob', 'binary', 'varbinary', 'text', 'mediumtext', 'longtext')
               OR COLUMN_NAME LIKE '%photo%' OR COLUMN_NAME LIKE '%image%')`,
    );
    assert.deepEqual(rows, []);
  });

  await t.test('deleting a user deletes their recognitions and items', async () => {
    const [u] = await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('photo@b.com', 'x', 'P')");
    const [r] = await pool.query(
      "INSERT INTO photo_recognitions (user_id, item_count, status) VALUES (?, 1, 'recognised')", [u.insertId],
    );
    await pool.query(
      `INSERT INTO photo_recognition_items (recognition_id, item_order, suggested_name, suggested_servings, alternative_food_ids)
       VALUES (?, 1, 'White rice', 1, '[]')`,
      [r.insertId],
    );
    await pool.query('DELETE FROM users WHERE user_id = ?', [u.insertId]);
    const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM photo_recognition_items WHERE recognition_id = ?', [r.insertId]);
    assert.equal(Number(n), 0);
  });
});
