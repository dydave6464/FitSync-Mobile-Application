'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('002 training schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const seed = async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (CONCAT('u', UUID(), '@b.com'), 'x', 'U')",
    );
    const [e] = await pool.query(
      "INSERT INTO exercises (name, muscle_group) VALUES (CONCAT('Ex ', UUID()), 'legs')",
    );
    return { userId: u.insertId, exerciseId: e.insertId };
  };

  await t.test('creates all six tables', async () => {
    const [rows] = await pool.query(
      `SELECT table_name AS t FROM information_schema.tables
       WHERE table_schema = ? AND table_name IN
       ('exercises','coaching_cues','workout_plans','plan_exercises','workout_sessions','set_logs')`,
      [testDbConfig().database],
    );
    assert.equal(rows.length, 6);
  });

  await t.test('an exercise defaults to pending with no reviewer (R-6)', async () => {
    const [res] = await pool.query(
      "INSERT INTO exercises (name, muscle_group) VALUES ('Squat', 'legs')",
    );
    const [rows] = await pool.query(
      'SELECT status, reviewed_by, animation_url, thumbnail_url, source_id FROM exercises WHERE exercise_id = ?',
      [res.insertId],
    );
    assert.equal(rows[0].status, 'pending');
    assert.equal(rows[0].reviewed_by, null);
    assert.equal(rows[0].animation_url, null);
    assert.equal(rows[0].thumbnail_url, null);
    assert.equal(rows[0].source_id, null, 'a hand-added exercise has no upstream id');
  });

  await t.test('source_id is unique, but many hand-added exercises may have none', async () => {
    await pool.query(
      "INSERT INTO exercises (source_id, name, muscle_group) VALUES ('0001', 'Seeded A', 'abs')",
    );
    await assert.rejects(
      () => pool.query(
        "INSERT INTO exercises (source_id, name, muscle_group) VALUES ('0001', 'Seeded B', 'abs')",
      ),
      (err) => {
        assert.equal(err.code, 'ER_DUP_ENTRY');
        return true;
      },
    );

    // NULL source_id must not collide with itself, or hand-added exercises
    // would be limited to a single row.
    await pool.query("INSERT INTO exercises (name, muscle_group) VALUES ('Manual A', 'abs')");
    await pool.query("INSERT INTO exercises (name, muscle_group) VALUES ('Manual B', 'abs')");
  });

  await t.test('two exercises may share a name — the dataset has 6 such pairs', async () => {
    await pool.query(
      "INSERT INTO exercises (source_id, name, muscle_group) VALUES ('9001', 'Shared Name', 'abs')",
    );
    await pool.query(
      "INSERT INTO exercises (source_id, name, muscle_group) VALUES ('9002', 'Shared Name', 'abs')",
    );
    const [rows] = await pool.query(
      "SELECT COUNT(*) AS n FROM exercises WHERE name = 'Shared Name'",
    );
    assert.equal(rows[0].n, 2);
  });

  await t.test('the same exercise may appear twice in one plan', async () => {
    const { userId, exerciseId } = await seed();
    const [p] = await pool.query(
      "INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min) VALUES (?, 'Plan', 'full_body', 3, 45)",
      [userId],
    );
    await pool.query(
      "INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps) VALUES (?, ?, 1, 3, '8-12')",
      [p.insertId, exerciseId],
    );
    await pool.query(
      "INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps) VALUES (?, ?, 5, 2, '12-15')",
      [p.insertId, exerciseId],
    );
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM plan_exercises WHERE plan_id = ?', [p.insertId]);
    assert.equal(rows[0].n, 2);
  });

  await t.test('deleting a session cascades to its set logs', async () => {
    const { userId, exerciseId } = await seed();
    const [s] = await pool.query(
      "INSERT INTO workout_sessions (user_id, session_date) VALUES (?, '2026-08-25')",
      [userId],
    );
    await pool.query(
      'INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps) VALUES (?, ?, 1, 60.00, 10)',
      [s.insertId, exerciseId],
    );
    await pool.query('DELETE FROM workout_sessions WHERE session_id = ?', [s.insertId]);
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM set_logs WHERE session_id = ?', [s.insertId]);
    assert.equal(rows[0].n, 0);
  });

  await t.test('total_volume_kg holds a realistic session volume', async () => {
    const { userId } = await seed();
    const [s] = await pool.query(
      "INSERT INTO workout_sessions (user_id, session_date, total_volume_kg) VALUES (?, '2026-08-25', 18450.50)",
      [userId],
    );
    const [rows] = await pool.query('SELECT total_volume_kg FROM workout_sessions WHERE session_id = ?', [s.insertId]);
    assert.equal(Number(rows[0].total_volume_kg), 18450.5);
  });

  await t.test('a retried "log set" request cannot insert a duplicate set', async () => {
    const { userId, exerciseId } = await seed();
    const [s] = await pool.query(
      "INSERT INTO workout_sessions (user_id, session_date) VALUES (?, '2026-08-25')",
      [userId],
    );
    await pool.query(
      'INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps) VALUES (?, ?, 1, 60.00, 10)',
      [s.insertId, exerciseId],
    );
    await assert.rejects(
      () =>
        pool.query(
          'INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps) VALUES (?, ?, 1, 60.00, 10)',
          [s.insertId, exerciseId],
        ),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('coaching cues cascade when their exercise is removed', async () => {
    const { exerciseId } = await seed();
    await pool.query(
      "INSERT INTO coaching_cues (exercise_id, order_no, cue_text) VALUES (?, 1, 'Keep your chest up')",
      [exerciseId],
    );
    await pool.query('DELETE FROM exercises WHERE exercise_id = ?', [exerciseId]);
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM coaching_cues WHERE exercise_id = ?', [exerciseId]);
    assert.equal(rows[0].n, 0);
  });
});
