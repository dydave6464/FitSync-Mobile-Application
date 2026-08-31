'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables, tableNames } = require('./helpers/test-db');

const EXPECTED_TABLES = [
  'activity_logs', 'admins', 'advertisements', 'body_weight_logs', 'coaching_cues',
  'equipment', 'exercise_contraindications', 'exercise_equipment_requirements',
  'exercises', 'food_recognitions', 'foods', 'goals', 'injuries',
  'injury_risk_estimates', 'meal_logs', 'morning_checkins', 'plan_exercises',
  'progress_reports', 'reminders', 'routine_items', 'set_logs', 'streaks',
  'subscriptions', 'user_equipment', 'user_identities', 'user_injuries', 'users',
  'workout_plans', 'workout_sessions',
];

test('complete FitSync schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('creates exactly the 29 tables from the data dictionary', async () => {
    const names = (await tableNames(pool)).filter((n) => n !== 'schema_migrations');
    assert.deepEqual(names.sort(), [...EXPECTED_TABLES].sort());
    assert.equal(names.length, 29);
  });

  await t.test('every table is InnoDB and utf8mb4', async () => {
    const [rows] = await pool.query(
      `SELECT table_name AS t, engine AS engine, table_collation AS c
       FROM information_schema.tables WHERE table_schema = ?`,
      [testDbConfig().database],
    );
    for (const row of rows) {
      assert.equal(row.engine, 'InnoDB', `${row.t} is not InnoDB`);
      assert.match(row.c, /^utf8mb4/, `${row.t} is not utf8mb4`);
    }
  });

  await t.test('every table has a single-column integer primary key (Table 5)', async () => {
    const [rows] = await pool.query(
      `SELECT table_name AS t, COUNT(*) AS cols
       FROM information_schema.key_column_usage
       WHERE table_schema = ? AND constraint_name = 'PRIMARY'
       GROUP BY table_name`,
      [testDbConfig().database],
    );
    const composite = rows.filter((r) => r.cols > 1 && r.t !== 'schema_migrations');
    assert.deepEqual(composite, [], 'no table may use a composite primary key');
    assert.equal(rows.length, 30); // 29 tables + schema_migrations
  });

  await t.test('a user has exactly one streak record', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('streak@b.com', 'x', 'S')",
    );
    await pool.query('INSERT INTO streaks (user_id, current_streak, best_streak) VALUES (?, 3, 9)', [u.insertId]);
    await assert.rejects(
      () => pool.query('INSERT INTO streaks (user_id) VALUES (?)', [u.insertId]),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('activity_logs rejects a second row for the same user and date', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('sync@b.com', 'x', 'Sync')",
    );
    await pool.query(
      "INSERT INTO activity_logs (user_id, log_date, steps) VALUES (?, '2026-08-25', 4000)",
      [u.insertId],
    );
    await assert.rejects(
      () =>
        pool.query(
          "INSERT INTO activity_logs (user_id, log_date, steps) VALUES (?, '2026-08-25', 6000)",
          [u.insertId],
        ),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('muscle balance defaults off — it is a premium section (C-10)', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('rep@b.com', 'x', 'R')",
    );
    const [r] = await pool.query(
      "INSERT INTO progress_reports (user_id, period_start, period_end) VALUES (?, '2026-08-01', '2026-08-25')",
      [u.insertId],
    );
    const [rows] = await pool.query(
      'SELECT include_volume, include_muscle_balance FROM progress_reports WHERE report_id = ?',
      [r.insertId],
    );
    assert.equal(rows[0].include_volume, 1);
    assert.equal(rows[0].include_muscle_balance, 0);
  });

  await t.test('deleting an admin keeps their advertisements (SET NULL)', async () => {
    const [a] = await pool.query(
      "INSERT INTO admins (email, password_hash, full_name) VALUES ('adm@b.com', 'x', 'Adm')",
    );
    const [ad] = await pool.query(
      "INSERT INTO advertisements (title, image_url, added_by) VALUES ('Promo', '/storage/ad.png', ?)",
      [a.insertId],
    );
    await pool.query('DELETE FROM admins WHERE admin_id = ?', [a.insertId]);
    const [rows] = await pool.query('SELECT added_by FROM advertisements WHERE ad_id = ?', [ad.insertId]);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].added_by, null);
  });

  await t.test('all nine migrations are recorded', async () => {
    const [rows] = await pool.query('SELECT version FROM schema_migrations ORDER BY version');
    assert.deepEqual(rows.map((r) => r.version), [
      '001_account_and_profile.sql',
      '002_training.sql',
      '003_recovery.sql',
      '004_nutrition.sql',
      '005_activity_motivation.sql',
      '006_reporting_monetization.sql',
      '007_auth_identities.sql',
      '008_equipment_curation.sql',
      '009_exercise_safety.sql',
    ]);
  });
});
