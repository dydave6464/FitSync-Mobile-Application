'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('nutrition tracking schema (032)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('n@b.com', 'x', 'N')",
  );
  const user = { user_id: u.insertId };

  await t.test('a FatSecret food maps to one foods row', async () => {
    const [f] = await pool.query("INSERT INTO foods (name, category, calories) VALUES ('Banana', 'international', 105)");
    await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', '35755')", [f.insertId]);
    const [g] = await pool.query("INSERT INTO foods (name, category, calories) VALUES ('Banana copy', 'international', 105)");
    await assert.rejects(
      pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', '35755')", [g.insertId]),
      /Duplicate entry/,
    );
  });

  await t.test('deleting the food deletes its source row', async () => {
    const [f] = await pool.query("INSERT INTO foods (name, category, calories) VALUES ('Apple', 'international', 95)");
    await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', '1')", [f.insertId]);
    await pool.query('DELETE FROM foods WHERE food_id = ?', [f.insertId]);
    const [rows] = await pool.query('SELECT * FROM food_sources WHERE food_id = ?', [f.insertId]);
    assert.equal(rows.length, 0);
  });

  await t.test('a manual entry keeps its serving text and fits 20 x 500 g', async () => {
    const [r] = await pool.query(
      `INSERT INTO meal_logs (user_id, custom_name, serving_desc, meal_type, servings, calories,
                              protein_g, carbs_g, fat_g, logged_via, log_date)
       VALUES (?, 'Big shake', '1 jug', 'snack', 20, 40000, 10000, 0, 0, 'manual', '2026-10-14')`,
      [user.user_id],
    );
    const [[row]] = await pool.query('SELECT serving_desc, protein_g FROM meal_logs WHERE meal_log_id = ?', [r.insertId]);
    assert.equal(row.serving_desc, '1 jug');
    assert.equal(Number(row.protein_g), 10000);
  });
});
