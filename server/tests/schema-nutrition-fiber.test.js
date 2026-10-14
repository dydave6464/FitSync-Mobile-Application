'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('nutrition fiber schema (033/034)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('fiber@b.com', 'x', 'F')",
  );
  const user = { user_id: u.insertId };

  await t.test('a food with no fiber leaves fiber_g NULL', async () => {
    const [f] = await pool.query("INSERT INTO foods (name, category, calories) VALUES ('Mystery food', 'international', 100)");
    const [[row]] = await pool.query('SELECT fiber_g FROM foods WHERE food_id = ?', [f.insertId]);
    assert.equal(row.fiber_g, null);
  });

  await t.test('a food fiber_g of 2.5 reads back as 2.5', async () => {
    const [f] = await pool.query(
      "INSERT INTO foods (name, category, calories, fiber_g) VALUES ('Fibrous food', 'international', 100, 2.5)",
    );
    const [[row]] = await pool.query('SELECT fiber_g FROM foods WHERE food_id = ?', [f.insertId]);
    assert.equal(Number(row.fiber_g), 2.5);
  });

  await t.test('a manual meal log with no fiber leaves fiber_g NULL', async () => {
    const [r] = await pool.query(
      `INSERT INTO meal_logs (user_id, custom_name, meal_type, calories, logged_via, log_date)
       VALUES (?, 'No fiber info', 'snack', 100, 'manual', '2026-10-14')`,
      [user.user_id],
    );
    const [[row]] = await pool.query('SELECT fiber_g FROM meal_logs WHERE meal_log_id = ?', [r.insertId]);
    assert.equal(row.fiber_g, null);
  });

  await t.test('a meal log fiber_g of 9999.99 fits (DECIMAL(7,2))', async () => {
    const [r] = await pool.query(
      `INSERT INTO meal_logs (user_id, custom_name, meal_type, calories, logged_via, log_date, fiber_g)
       VALUES (?, 'Big fiber shake', 'snack', 100, 'manual', '2026-10-14', 9999.99)`,
      [user.user_id],
    );
    const [[row]] = await pool.query('SELECT fiber_g FROM meal_logs WHERE meal_log_id = ?', [r.insertId]);
    assert.equal(Number(row.fiber_g), 9999.99);
  });
});
