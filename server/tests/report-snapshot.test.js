'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');
const { buildReportSnapshot, SECTIONS } = require('../src/db/report-snapshot');

test('report snapshot', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  const [ex] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE status='live' LIMIT 1",
  );
  const exerciseId = ex[0].exercise_id;

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const all = { volume: true, bodyWeight: true, muscles: true, sessions: true };

  const trainedUser = async (email) => {
    const [u] = await pool.query(
      'INSERT INTO users (email, password_hash, full_name) VALUES (?, ?, ?)',
      [email, 'x', 'R'],
    );
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date, total_volume_kg)
       VALUES (?, 'completed', CURDATE(), 600)`,
      [u.insertId],
    );
    await pool.query(
      `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
       VALUES (?, ?, 1, 60, 10, TRUE)`,
      [s.insertId, exerciseId],
    );
    await pool.query(
      'INSERT INTO body_weight_logs (user_id, weight_kg, log_date) VALUES (?, 71.5, CURDATE())',
      [u.insertId],
    );
    return u.insertId;
  };

  await t.test('every section is present when all are asked for', async () => {
    const userId = await trainedUser('s1@example.com');
    const snap = await buildReportSnapshot(pool, userId, {
      period: 'week', include: all, premium: true,
    });

    for (const key of SECTIONS) {
      assert.notEqual(snap[key], null, `${key} should be captured`);
    }
    // 1 set x 60 kg x 10 reps, hand-derived.
    assert.equal(snap.summary.totalVolumeKg, 600);
    assert.equal(snap.summary.sessionCount, 1);
    assert.equal(snap.summary.setCount, 1);
  });

  // An excluded section is not hidden by the page -- it was never captured.
  // That is what makes the toggles mean something.
  await t.test('an excluded section is absent from the snapshot', async () => {
    const userId = await trainedUser('s2@example.com');
    const snap = await buildReportSnapshot(pool, userId, {
      period: 'week',
      include: { volume: true, bodyWeight: false, muscles: false, sessions: false },
      premium: true,
    });

    assert.notEqual(snap.volume, null);
    assert.equal(snap.bodyWeight, null);
    assert.equal(snap.muscles, null);
    assert.equal(snap.sessions, null);
  });

  // Muscle balance is the Pro section. Asking for it without Pro yields
  // nothing rather than an error: the rest of the report is still valid.
  await t.test('a free user gets no muscle section even when asked for', async () => {
    const userId = await trainedUser('s3@example.com');
    const snap = await buildReportSnapshot(pool, userId, {
      period: 'week', include: all, premium: false,
    });

    assert.equal(snap.muscles, null);
    assert.notEqual(snap.volume, null, 'the free sections still come through');
  });

  // The summary row is the report's header and is not a toggleable section,
  // so it survives every section being switched off.
  await t.test('the summary is captured whatever the toggles say', async () => {
    const userId = await trainedUser('s4@example.com');
    const snap = await buildReportSnapshot(pool, userId, {
      period: 'week',
      include: { volume: false, bodyWeight: false, muscles: false, sessions: false },
      premium: true,
    });

    assert.equal(snap.summary.sessionCount, 1);
  });
});
