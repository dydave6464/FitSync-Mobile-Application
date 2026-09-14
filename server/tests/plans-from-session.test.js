'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { createPlanFromSession } = require('../src/db/plans');
const { nextPlanDayNo } = require('../src/db/sessions');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('building a plan out of a completed session', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const [live] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE status='live' ORDER BY exercise_id LIMIT 3",
  );

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const [u] = await pool.query(
      'INSERT INTO users (email, password_hash, full_name) VALUES (?, ?, ?)',
      [`fs${seq}@example.com`, 'x', 'FS'],
    );
    return u.insertId;
  };

  /// A finished hand-picked session, with real logged sets so the derived
  /// prescription has something to read.
  const completedManualSession = async (userId, exerciseIds, {
    setsEach = 3, reps = 10, minutes = 45,
  } = {}) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions
         (user_id, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, 'completed', CURDATE(), NOW(), ?, 1000)`,
      [userId, minutes],
    );
    for (const [i, id] of exerciseIds.entries()) {
      await pool.query(
        'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES (?, ?, ?)',
        [s.insertId, id, i + 1],
      );
      for (let n = 1; n <= setsEach; n += 1) {
        await pool.query(
          `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps)
           VALUES (?, ?, ?, 20, ?)`,
          [s.insertId, id, n, reps],
        );
      }
    }
    return s.insertId;
  };

  const activePlan = async (userId) => {
    const [[plan]] = await pool.query(
      `SELECT plan_id, name, split_style, days_per_week, session_length_min, week_no, source
         FROM workout_plans WHERE user_id = ? AND is_active = TRUE`,
      [userId],
    );
    return plan;
  };

  const planDays = async (planId) => {
    const [rows] = await pool.query(
      `SELECT day_no, exercise_id, order_no, target_sets, target_reps
         FROM plan_exercises WHERE plan_id = ? ORDER BY day_no, order_no`,
      [planId],
    );
    return rows;
  };

  await t.test('a completed session becomes day 1 of a custom plan', async () => {
    const userId = await freshUser();
    const sessionId = await completedManualSession(
      userId, [live[0].exercise_id, live[1].exercise_id],
    );

    await createPlanFromSession(pool, userId, {
      sessionId, splitStyle: 'push_pull_legs',
    });

    const plan = await activePlan(userId);
    assert.equal(plan.source, 'custom');
    assert.equal(plan.split_style, 'push_pull_legs');
    assert.equal(plan.week_no, 1);

    const days = await planDays(plan.plan_id);
    assert.deepEqual(days.map((d) => d.day_no), [1, 1]);
    assert.deepEqual(days.map((d) => d.exercise_id),
      [live[0].exercise_id, live[1].exercise_id]);
    assert.deepEqual(days.map((d) => d.order_no), [1, 2]);
  });

  await t.test('creating a custom plan switches the generated one off', async () => {
    // savePlan's one-active-plan invariant, kept: the Plan tab, Home card and
    // rotation all read "the active plan", and two would make that ambiguous.
    const userId = await freshUser();
    const [gen] = await pool.query(
      `INSERT INTO workout_plans
         (user_id, name, split_style, days_per_week, session_length_min, is_active, source)
       VALUES (?, 'Generated', 'full_body', 3, 45, TRUE, 'generated')`,
      [userId],
    );
    const sessionId = await completedManualSession(userId, [live[0].exercise_id]);

    await createPlanFromSession(pool, userId, {
      sessionId, splitStyle: 'full_body',
    });

    const [[old]] = await pool.query(
      'SELECT is_active FROM workout_plans WHERE plan_id = ?', [gen.insertId],
    );
    assert.equal(old.is_active, 0);
    assert.equal((await activePlan(userId)).source, 'custom');
  });

  await t.test('the plan is named after the split the user chose', async () => {
    const userId = await freshUser();
    const sessionId = await completedManualSession(userId, [live[0].exercise_id]);

    await createPlanFromSession(pool, userId, {
      sessionId, splitStyle: 'push_pull_legs',
    });

    assert.equal((await activePlan(userId)).name, 'My Push / Pull / Legs');
  });

  await t.test('another account\'s session cannot be taken', async () => {
    const mine = await freshUser();
    const theirs = await freshUser();
    const sessionId = await completedManualSession(theirs, [live[0].exercise_id]);

    await assert.rejects(
      () => createPlanFromSession(pool, mine, { sessionId, splitStyle: 'full_body' }),
      (err) => err.code === 'SESSION_NOT_FOUND',
    );
  });

  await t.test('an unfinished session is not a plan day', async () => {
    const userId = await freshUser();
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date, started_at)
       VALUES (?, 'in_progress', CURDATE(), NOW())`,
      [userId],
    );

    await assert.rejects(
      () => createPlanFromSession(pool, userId, {
        sessionId: s.insertId, splitStyle: 'full_body',
      }),
      (err) => err.code === 'SESSION_NOT_COMPLETED',
    );
  });

  await t.test('a session with no live exercise is refused', async () => {
    const userId = await freshUser();
    const sessionId = await completedManualSession(userId, [live[0].exercise_id]);
    await pool.query("UPDATE exercises SET status='pending' WHERE exercise_id = ?",
      [live[0].exercise_id]);

    await assert.rejects(
      () => createPlanFromSession(pool, userId, { sessionId, splitStyle: 'full_body' }),
      (err) => err.code === 'SESSION_HAS_NO_EXERCISES',
    );

    await pool.query("UPDATE exercises SET status='live' WHERE exercise_id = ?",
      [live[0].exercise_id]);
  });

  await t.test('nothing is written when the session is refused', async () => {
    // The whole write is one transaction: a refusal halfway through must not
    // leave a plan row with no exercises, which the Plan tab would render as
    // an empty week.
    const userId = await freshUser();
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date, started_at)
       VALUES (?, 'abandoned', CURDATE(), NOW())`,
      [userId],
    );

    await assert.rejects(() => createPlanFromSession(pool, userId, {
      sessionId: s.insertId, splitStyle: 'full_body',
    }));

    const [plans] = await pool.query(
      'SELECT plan_id FROM workout_plans WHERE user_id = ?', [userId],
    );
    assert.equal(plans.length, 0);
  });
});
