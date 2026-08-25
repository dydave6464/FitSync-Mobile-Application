'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('001 account and profile schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('creates all eight tables', async () => {
    const [rows] = await pool.query(
      `SELECT table_name AS t FROM information_schema.tables
       WHERE table_schema = ? AND table_name IN
       ('users','admins','goals','equipment','user_equipment','injuries','user_injuries','subscriptions')`,
      [testDbConfig().database],
    );
    assert.equal(rows.length, 8);
  });

  await t.test('users.email is unique', async () => {
    await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('a@b.com', 'x', 'A B')",
    );
    await assert.rejects(
      () => pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('a@b.com', 'y', 'C D')"),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('a user can be created before onboarding fields are known', async () => {
    const [res] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('pre@onboard.com', 'x', 'Pre Onboard')",
    );
    const [rows] = await pool.query('SELECT main_goal, fitness_level, is_premium FROM users WHERE user_id = ?', [res.insertId]);
    assert.equal(rows[0].main_goal, null);
    assert.equal(rows[0].fitness_level, null);
    assert.equal(rows[0].is_premium, 0);
  });

  await t.test('fitness_level accepts only beginner and intermediate (C-1)', async () => {
    await assert.rejects(
      () => pool.query(
        "INSERT INTO users (email, password_hash, full_name, fitness_level) VALUES ('adv@b.com','x','Adv','advanced')",
      ),
    );
  });

  await t.test('a user may hold more than one subscription over time', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('sub@b.com', 'x', 'Sub')",
    );
    await pool.query(
      "INSERT INTO subscriptions (user_id, plan, price_php, status) VALUES (?, 'monthly', 199.00, 'expired')",
      [u.insertId],
    );
    await pool.query(
      "INSERT INTO subscriptions (user_id, plan, price_php, status) VALUES (?, 'monthly', 199.00, 'active')",
      [u.insertId],
    );
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM subscriptions WHERE user_id = ?', [u.insertId]);
    assert.equal(rows[0].n, 2);
  });

  await t.test('user_equipment rejects duplicate pairings', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('eq@b.com', 'x', 'Eq')",
    );
    const [e] = await pool.query("INSERT INTO equipment (name) VALUES ('Dumbbell')");
    await pool.query('INSERT INTO user_equipment (user_id, equipment_id) VALUES (?, ?)', [u.insertId, e.insertId]);
    await assert.rejects(
      () => pool.query('INSERT INTO user_equipment (user_id, equipment_id) VALUES (?, ?)', [u.insertId, e.insertId]),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('deleting a user cascades to their goals', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('cascade@b.com', 'x', 'Cas')",
    );
    await pool.query("INSERT INTO goals (user_id, title) VALUES (?, 'Lose 5kg')", [u.insertId]);
    await pool.query('DELETE FROM users WHERE user_id = ?', [u.insertId]);
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM goals WHERE user_id = ?', [u.insertId]);
    assert.equal(rows[0].n, 0);
  });

  await t.test('equipment in use cannot be deleted', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('restrict@b.com', 'x', 'Res')",
    );
    const [e] = await pool.query("INSERT INTO equipment (name) VALUES ('Barbell')");
    await pool.query('INSERT INTO user_equipment (user_id, equipment_id) VALUES (?, ?)', [u.insertId, e.insertId]);
    await assert.rejects(
      () => pool.query('DELETE FROM equipment WHERE equipment_id = ?', [e.insertId]),
      (err) => err.code === 'ER_ROW_IS_REFERENCED_2',
    );
  });
});
