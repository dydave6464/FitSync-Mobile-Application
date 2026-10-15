'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('nutrition sugar/sodium schema (035/036)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('sugarsodium@b.com', 'x', 'S')",
  );
  const user = { user_id: u.insertId };

  await t.test('a food with no sugar or sodium leaves sugar_g and sodium_mg NULL', async () => {
    const [f] = await pool.query("INSERT INTO foods (name, category, calories) VALUES ('Mystery food', 'international', 100)");
    const [[row]] = await pool.query('SELECT sugar_g, sodium_mg FROM foods WHERE food_id = ?', [f.insertId]);
    assert.equal(row.sugar_g, null);
    assert.equal(row.sodium_mg, null);
  });

  await t.test('a food sugar_g of 9.7 and sodium_mg of 124 read back as 9.7 and 124', async () => {
    const [f] = await pool.query(
      "INSERT INTO foods (name, category, calories, sugar_g, sodium_mg) VALUES ('Sweet salty food', 'international', 100, 9.7, 124)",
    );
    const [[row]] = await pool.query('SELECT sugar_g, sodium_mg FROM foods WHERE food_id = ?', [f.insertId]);
    assert.equal(Number(row.sugar_g), 9.7);
    assert.equal(Number(row.sodium_mg), 124);
  });

  await t.test('a manual meal log with no sugar or sodium leaves sugar_g and sodium_mg NULL', async () => {
    const [r] = await pool.query(
      `INSERT INTO meal_logs (user_id, custom_name, meal_type, calories, logged_via, log_date)
       VALUES (?, 'No sugar or sodium info', 'snack', 100, 'manual', '2026-10-14')`,
      [user.user_id],
    );
    const [[row]] = await pool.query('SELECT sugar_g, sodium_mg FROM meal_logs WHERE meal_log_id = ?', [r.insertId]);
    assert.equal(row.sugar_g, null);
    assert.equal(row.sodium_mg, null);
  });

  await t.test('a meal log sugar_g of 9999.99 and sodium_mg of 199999.5 fit (DECIMAL(7,2)/DECIMAL(9,1))', async () => {
    const [r] = await pool.query(
      `INSERT INTO meal_logs (user_id, custom_name, meal_type, calories, logged_via, log_date, sugar_g, sodium_mg)
       VALUES (?, 'Big sugar and sodium shake', 'snack', 100, 'manual', '2026-10-14', 9999.99, 199999.5)`,
      [user.user_id],
    );
    const [[row]] = await pool.query('SELECT sugar_g, sodium_mg FROM meal_logs WHERE meal_log_id = ?', [r.insertId]);
    assert.equal(Number(row.sugar_g), 9999.99);
    assert.equal(Number(row.sodium_mg), 199999.5);
  });
});
