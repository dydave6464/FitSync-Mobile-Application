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

  await t.test('a second workout becomes day 2 of the same plan', async () => {
    const userId = await freshUser();
    const first = await completedManualSession(userId, [live[0].exercise_id]);
    await createPlanFromSession(pool, userId, {
      sessionId: first, splitStyle: 'push_pull_legs',
    });
    const planId = (await activePlan(userId)).plan_id;

    const second = await completedManualSession(userId, [live[1].exercise_id]);
    await createPlanFromSession(pool, userId, { sessionId: second });

    // The same plan row, not a second one: the plan accumulates.
    assert.equal((await activePlan(userId)).plan_id, planId);
    const days = await planDays(planId);
    assert.deepEqual(days.map((d) => d.day_no), [1, 2]);
    assert.deepEqual(days.map((d) => d.exercise_id),
      [live[0].exercise_id, live[1].exercise_id]);
  });

  await t.test('only one plan row exists after appending', async () => {
    const userId = await freshUser();
    const first = await completedManualSession(userId, [live[0].exercise_id]);
    await createPlanFromSession(pool, userId, {
      sessionId: first, splitStyle: 'full_body',
    });
    const second = await completedManualSession(userId, [live[1].exercise_id]);
    await createPlanFromSession(pool, userId, { sessionId: second });

    const [plans] = await pool.query(
      'SELECT plan_id FROM workout_plans WHERE user_id = ?', [userId],
    );
    assert.equal(plans.length, 1);
  });

  await t.test('a named day is replaced, and the others are left alone', async () => {
    const userId = await freshUser();
    const first = await completedManualSession(userId, [live[0].exercise_id]);
    await createPlanFromSession(pool, userId, {
      sessionId: first, splitStyle: 'full_body',
    });
    const second = await completedManualSession(userId, [live[1].exercise_id]);
    await createPlanFromSession(pool, userId, { sessionId: second });
    const planId = (await activePlan(userId)).plan_id;

    const third = await completedManualSession(userId, [live[2].exercise_id]);
    await createPlanFromSession(pool, userId, { sessionId: third, dayNo: 1 });

    const days = await planDays(planId);
    assert.deepEqual(days.map((d) => d.day_no), [1, 2]);
    assert.equal(days[0].exercise_id, live[2].exercise_id, 'day 1 was replaced');
    assert.equal(days[1].exercise_id, live[1].exercise_id, 'day 2 untouched');
  });

  await t.test('a day beyond the end of the plan is refused', async () => {
    // Accepting it would leave a gap -- day 1 and day 5 with nothing between,
    // which nextPlanDayNo would rotate through as if the gap were trainable.
    const userId = await freshUser();
    const first = await completedManualSession(userId, [live[0].exercise_id]);
    await createPlanFromSession(pool, userId, {
      sessionId: first, splitStyle: 'full_body',
    });

    const second = await completedManualSession(userId, [live[1].exercise_id]);
    await assert.rejects(
      () => createPlanFromSession(pool, userId, { sessionId: second, dayNo: 5 }),
      (err) => err.code === 'INVALID_DAY_NO',
    );
  });

  await t.test('a custom plan rotates exactly as a generated one does', async () => {
    // Spec section 5's claim, proven rather than asserted: nothing that
    // FOLLOWS a plan changes, because a custom plan is the same shape as a
    // generated one. nextPlanDayNo derives the day from MAX(day_no) and the
    // week's completed-session count, neither of which knows about source.
    const userId = await freshUser();
    for (let day = 0; day < 3; day += 1) {
      const s = await completedManualSession(userId, [live[day].exercise_id]);
      // The first call creates the plan; splitStyle is ignored by the two
      // that extend it.
      await createPlanFromSession(pool, userId, {
        sessionId: s, splitStyle: 'push_pull_legs',
      });
    }

    const planId = (await activePlan(userId)).plan_id;
    const [[{ rotation }]] = await pool.query(
      'SELECT MAX(day_no) AS rotation FROM plan_exercises WHERE plan_id = ?', [planId],
    );
    assert.equal(Number(rotation), 3, 'three days were built');

    // Three sessions were completed this week building it, so the next day is
    // (3 % 3) + 1 = 1 -- the rotation wrapping, exactly as it would for a
    // generated three-day plan.
    assert.equal(await nextPlanDayNo(pool, userId, Number(rotation)), 1);
  });

  await t.test('a generated active plan is replaced, not extended', async () => {
    // "Does a custom plan exist" is the wrong question -- one the generator
    // already replaced is deactivated, and reviving it is out of scope.
    const userId = await freshUser();
    const first = await completedManualSession(userId, [live[0].exercise_id]);
    await createPlanFromSession(pool, userId, {
      sessionId: first, splitStyle: 'full_body',
    });
    const firstPlanId = (await activePlan(userId)).plan_id;

    await pool.query('UPDATE workout_plans SET is_active = FALSE WHERE user_id = ?', [userId]);
    await pool.query(
      `INSERT INTO workout_plans
         (user_id, name, split_style, days_per_week, session_length_min, is_active, source)
       VALUES (?, 'Generated', 'full_body', 3, 45, TRUE, 'generated')`,
      [userId],
    );

    const second = await completedManualSession(userId, [live[1].exercise_id]);
    await createPlanFromSession(pool, userId, {
      sessionId: second, splitStyle: 'full_body',
    });

    const plan = await activePlan(userId);
    assert.equal(plan.source, 'custom');
    assert.notEqual(plan.plan_id, firstPlanId, 'a fresh custom plan, not the old one');
    assert.deepEqual((await planDays(plan.plan_id)).map((d) => d.day_no), [1]);
  });

  await t.test('the prescription is what the user actually did', async () => {
    // More honest than the generator's guess: these are sets and reps this
    // person performed, not a target somebody assumed for them.
    const userId = await freshUser();
    const sessionId = await completedManualSession(
      userId, [live[0].exercise_id], { setsEach: 4, reps: 12 },
    );

    await createPlanFromSession(pool, userId, { sessionId, splitStyle: 'full_body' });

    const [day] = await planDays((await activePlan(userId)).plan_id);
    assert.equal(day.target_sets, 4);
    assert.equal(day.target_reps, '12');
  });

  await t.test('the most frequently logged rep count wins', async () => {
    const userId = await freshUser();
    const [s] = await pool.query(
      `INSERT INTO workout_sessions
         (user_id, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, 'completed', CURDATE(), NOW(), 45, 500)`,
      [userId],
    );
    await pool.query(
      'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES (?, ?, 1)',
      [s.insertId, live[0].exercise_id],
    );
    for (const [n, reps] of [[1, 8], [2, 10], [3, 10]]) {
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps)
         VALUES (?, ?, ?, 20, ?)`,
        [s.insertId, live[0].exercise_id, n, reps],
      );
    }

    await createPlanFromSession(pool, userId, {
      sessionId: s.insertId, splitStyle: 'full_body',
    });

    const [day] = await planDays((await activePlan(userId)).plan_id);
    assert.equal(day.target_sets, 3);
    // 10 appears twice against 8's once -- n=2 beats n=1 outright, so this
    // is not a tie. See the two genuine-tie subtests below for that case.
    assert.equal(day.target_reps, '10');
  });

  await t.test('a genuine tie between rep counts goes to the higher, logged low then high', async () => {
    // One set at 8 reps, one set at 10 -- an honest tie in set count (n=1
    // each), unlike the n=2-vs-n=1 case above. A user who did 8 then 10 is
    // more likely chasing 10 than settling for 8, so the higher value wins.
    const userId = await freshUser();
    const [s] = await pool.query(
      `INSERT INTO workout_sessions
         (user_id, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, 'completed', CURDATE(), NOW(), 45, 500)`,
      [userId],
    );
    await pool.query(
      'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES (?, ?, 1)',
      [s.insertId, live[0].exercise_id],
    );
    for (const [n, reps] of [[1, 8], [2, 10]]) {
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps)
         VALUES (?, ?, ?, 20, ?)`,
        [s.insertId, live[0].exercise_id, n, reps],
      );
    }

    await createPlanFromSession(pool, userId, {
      sessionId: s.insertId, splitStyle: 'full_body',
    });

    const [day] = await planDays((await activePlan(userId)).plan_id);
    assert.equal(day.target_reps, '10');
  });

  await t.test('a genuine tie between rep counts goes to the higher, logged high then low', async () => {
    // Same tie as above, logged in the opposite order. The comparator must
    // not depend on which rep value the grouped query happens to hand it
    // first -- a user who logged 10 then settled for 8 is still, on the
    // balance of one set each, more plausibly chasing 10.
    const userId = await freshUser();
    const [s] = await pool.query(
      `INSERT INTO workout_sessions
         (user_id, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, 'completed', CURDATE(), NOW(), 45, 500)`,
      [userId],
    );
    await pool.query(
      'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES (?, ?, 1)',
      [s.insertId, live[0].exercise_id],
    );
    for (const [n, reps] of [[1, 10], [2, 8]]) {
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps)
         VALUES (?, ?, ?, 20, ?)`,
        [s.insertId, live[0].exercise_id, n, reps],
      );
    }

    await createPlanFromSession(pool, userId, {
      sessionId: s.insertId, splitStyle: 'full_body',
    });

    const [day] = await planDays((await activePlan(userId)).plan_id);
    assert.equal(day.target_reps, '10');
  });

  await t.test('a set with no reps falls back to the stock prescription', async () => {
    // An AMRAP or an untracked bodyweight movement. "null reps" is not a
    // prescription the logger can render.
    const userId = await freshUser();
    const [s] = await pool.query(
      `INSERT INTO workout_sessions
         (user_id, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, 'completed', CURDATE(), NOW(), 45, 0)`,
      [userId],
    );
    await pool.query(
      'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES (?, ?, 1)',
      [s.insertId, live[0].exercise_id],
    );
    await pool.query(
      `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps)
       VALUES (?, ?, 1, NULL, NULL)`,
      [s.insertId, live[0].exercise_id],
    );

    await createPlanFromSession(pool, userId, {
      sessionId: s.insertId, splitStyle: 'full_body',
    });

    const [day] = await planDays((await activePlan(userId)).plan_id);
    assert.equal(day.target_sets, 1, 'the set happened even if the reps were not counted');
    assert.equal(day.target_reps, '8-12');
  });

  await t.test('an exercise with no logged set keeps the stock prescription', async () => {
    const userId = await freshUser();
    const [s] = await pool.query(
      `INSERT INTO workout_sessions
         (user_id, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, 'completed', CURDATE(), NOW(), 45, 0)`,
      [userId],
    );
    await pool.query(
      'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES (?, ?, 1)',
      [s.insertId, live[0].exercise_id],
    );

    await createPlanFromSession(pool, userId, {
      sessionId: s.insertId, splitStyle: 'full_body',
    });

    const [day] = await planDays((await activePlan(userId)).plan_id);
    assert.equal(day.target_sets, 3);
    assert.equal(day.target_reps, '8-12');
  });

  await t.test('days per week comes from the days the user trains', async () => {
    const userId = await freshUser();
    for (const weekday of [1, 3, 5]) {
      await pool.query(
        'INSERT INTO user_training_days (user_id, weekday) VALUES (?, ?)',
        [userId, weekday],
      );
    }
    const sessionId = await completedManualSession(userId, [live[0].exercise_id]);

    await createPlanFromSession(pool, userId, { sessionId, splitStyle: 'push_pull_legs' });

    assert.equal((await activePlan(userId)).days_per_week, 3);
  });

  await t.test('with no chosen days, the plan\'s own day count stands in', async () => {
    const userId = await freshUser();
    const sessionId = await completedManualSession(userId, [live[0].exercise_id]);

    await createPlanFromSession(pool, userId, { sessionId, splitStyle: 'full_body' });

    assert.equal((await activePlan(userId)).days_per_week, 1);
  });

  await t.test('session length is the mean of what the workouts took', async () => {
    const userId = await freshUser();
    const first = await completedManualSession(
      userId, [live[0].exercise_id], { minutes: 30 },
    );
    await createPlanFromSession(pool, userId, {
      sessionId: first, splitStyle: 'full_body',
    });
    const second = await completedManualSession(
      userId, [live[1].exercise_id], { minutes: 50 },
    );
    await createPlanFromSession(pool, userId, { sessionId: second });

    assert.equal((await activePlan(userId)).session_length_min, 40);
  });

  await t.test('a wild duration is clamped to the generator\'s own bounds', async () => {
    const userId = await freshUser();
    const sessionId = await completedManualSession(
      userId, [live[0].exercise_id], { minutes: 600 },
    );

    await createPlanFromSession(pool, userId, { sessionId, splitStyle: 'full_body' });

    assert.equal((await activePlan(userId)).session_length_min, 120);
  });
});
