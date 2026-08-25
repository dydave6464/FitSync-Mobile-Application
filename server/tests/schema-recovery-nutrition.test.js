'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('003 recovery and 004 nutrition schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const newUser = async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (CONCAT('u', UUID(), '@b.com'), 'x', 'U')",
    );
    return u.insertId;
  };

  await t.test('creates all five tables', async () => {
    const [rows] = await pool.query(
      `SELECT table_name AS t FROM information_schema.tables
       WHERE table_schema = ? AND table_name IN
       ('morning_checkins','injury_risk_estimates','foods','meal_logs','food_recognitions')`,
      [testDbConfig().database],
    );
    assert.equal(rows.length, 5);
  });

  await t.test('a user may check in only once per day (FR-5.1)', async () => {
    const userId = await newUser();
    const values = "'good','mild','moderate','low'";
    await pool.query(
      `INSERT INTO morning_checkins (user_id, checkin_date, sleep_quality, muscle_soreness, energy, stress)
       VALUES (?, '2026-08-25', ${values})`,
      [userId],
    );
    await assert.rejects(
      () => pool.query(
        `INSERT INTO morning_checkins (user_id, checkin_date, sleep_quality, muscle_soreness, energy, stress)
         VALUES (?, '2026-08-25', ${values})`,
        [userId],
      ),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('an injury risk estimate links to its check-in', async () => {
    const userId = await newUser();
    const [c] = await pool.query(
      `INSERT INTO morning_checkins (user_id, checkin_date, sleep_quality, muscle_soreness, energy, stress)
       VALUES (?, '2026-08-26', 'poor','severe','low','high')`,
      [userId],
    );
    await pool.query(
      "INSERT INTO injury_risk_estimates (user_id, checkin_id, risk_level, training_load_score) VALUES (?, ?, 'high', 82.50)",
      [userId, c.insertId],
    );
    const [rows] = await pool.query('SELECT risk_level FROM injury_risk_estimates WHERE checkin_id = ?', [c.insertId]);
    assert.equal(rows[0].risk_level, 'high');
  });

  await t.test('a meal log needs either a catalogue food or a custom name (R-6)', async () => {
    const userId = await newUser();
    await assert.rejects(
      () => pool.query(
        `INSERT INTO meal_logs (user_id, meal_type, calories, logged_via, log_date)
         VALUES (?, 'lunch', 500, 'manual', '2026-08-25')`,
        [userId],
      ),
    );
  });

  await t.test('a manually named meal logs without a food row', async () => {
    const userId = await newUser();
    const [res] = await pool.query(
      `INSERT INTO meal_logs (user_id, custom_name, meal_type, calories, logged_via, log_date)
       VALUES (?, 'Lola adobo', 'lunch', 650, 'manual', '2026-08-25')`,
      [userId],
    );
    const [rows] = await pool.query('SELECT food_id, custom_name FROM meal_logs WHERE meal_log_id = ?', [res.insertId]);
    assert.equal(rows[0].food_id, null);
    assert.equal(rows[0].custom_name, 'Lola adobo');
  });

  await t.test('Filipino dish names survive utf8mb4 round-tripping', async () => {
    const [res] = await pool.query(
      "INSERT INTO foods (name, category, calories) VALUES ('Sinigang na baboy — maasim 🍲', 'filipino', 320)",
    );
    const [rows] = await pool.query('SELECT name FROM foods WHERE food_id = ?', [res.insertId]);
    assert.equal(rows[0].name, 'Sinigang na baboy — maasim 🍲');
  });

  await t.test('a recognition starts unconfirmed with no meal log (FR-6.3, C-5)', async () => {
    const userId = await newUser();
    const [res] = await pool.query(
      "INSERT INTO food_recognitions (user_id, photo_url, match_confidence) VALUES (?, '/storage/a.jpg', 0.873)",
      [userId],
    );
    const [rows] = await pool.query(
      'SELECT is_confirmed, meal_log_id, match_confidence FROM food_recognitions WHERE recognition_id = ?',
      [res.insertId],
    );
    assert.equal(rows[0].is_confirmed, 0);
    assert.equal(rows[0].meal_log_id, null);
    assert.equal(Number(rows[0].match_confidence), 0.873);
  });
});
