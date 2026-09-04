'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { seedInjuries } = require('../src/db/seed-injuries');
const { savePlan, getActivePlan } = require('../src/db/plans');
const { loadSwapContext, listAlternatives, swapPlanExercise } = require('../src/db/plan-swap');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('swap candidates', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  // `injuries` is populated only by seed-injuries.js -- no migration inserts
  // rows -- so the contraindication tests below would read an empty table
  // without this. Same setup profile-db.test.js uses.
  await seedInjuries(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  // Two live exercises sharing a muscle group: one goes in the plan, the other
  // is the alternative that must come back.
  const [pair] = await pool.query(
    `SELECT x.exercise_id, x.name, x.muscle_group
       FROM exercises x
      WHERE x.status = 'live'
        AND x.muscle_group = (SELECT muscle_group FROM exercises
                               WHERE status='live' GROUP BY muscle_group
                              HAVING COUNT(*) >= 2 LIMIT 1)
      ORDER BY x.exercise_id LIMIT 2`,
  );
  const [inPlan, other] = pair;

  let userId;
  const reset = async () => {
    await pool.query('DELETE FROM plan_exercises');
    await pool.query('DELETE FROM workout_plans');
    await pool.query('DELETE FROM user_equipment');
    await pool.query('DELETE FROM user_injuries');
    // Subtests 3 and 4 both contraindicate the same (other.exercise_id,
    // injury) pair -- injuries is never mutated after seedInjuries, so
    // `SELECT injury_id FROM injuries LIMIT 1` is the same row every time.
    // Without this, the second subtest's insert collides with the first's on
    // uq_ec (exercise_id, injury_id) instead of exercising the query.
    await pool.query('DELETE FROM exercise_contraindications');
    await pool.query('DELETE FROM users');
    const [r] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('s@example.com','x','S')",
    );
    userId = r.insertId;
    await savePlan(pool, userId, {
      name: 'P', splitStyle: 'full_body', daysPerWeek: 3, sessionLengthMin: 45, weekNo: 1,
      exercises: [{ name: inPlan.name, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
    });
    const plan = await getActivePlan(pool, userId);
    return plan.exercises[0].planExerciseId;
  };

  await t.test('refuses a row belonging to another user', async () => {
    const planExerciseId = await reset();
    const [r] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('other@example.com','x','O')",
    );
    assert.equal(await loadSwapContext(pool, r.insertId, planExerciseId), null,
      'one user must not read another user’s plan row');
  });

  await t.test('refuses a row on a plan that has been superseded', async () => {
    const planExerciseId = await reset();
    // savePlan sets is_active = FALSE on the previous plan but leaves its
    // rows in place -- exactly what a re-issued POST
    // /profile/complete-onboarding produces. A client still holding ids from
    // that now-archived plan must not be able to write through them.
    await savePlan(pool, userId, {
      name: 'P2', splitStyle: 'full_body', daysPerWeek: 3, sessionLengthMin: 45, weekNo: 1,
      exercises: [{ name: inPlan.name, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
    });
    assert.equal(await loadSwapContext(pool, userId, planExerciseId), null,
      'a superseded plan row must 404 like any other unreachable row');
  });

  await t.test('offers a same-muscle exercise that is not already in the plan', async () => {
    const planExerciseId = await reset();
    const ctx = await loadSwapContext(pool, userId, planExerciseId);
    const rows = await listAlternatives(pool, ctx, { q: null, limit: 20 });
    const ids = rows.map((r) => r.exerciseId);

    assert.ok(ids.includes(other.exercise_id), 'the sibling exercise must be offered');
    assert.ok(!ids.includes(inPlan.exercise_id), 'what is already in the plan is not an alternative');
    assert.ok(rows.every((r) => r.muscleGroup === inPlan.muscle_group),
      'suggestions stay in the muscle group being replaced');
  });

  await t.test('never offers an exercise contraindicated for a reported injury', async () => {
    const planExerciseId = await reset();
    const [inj] = await pool.query('SELECT injury_id FROM injuries LIMIT 1');
    const injuryId = inj[0].injury_id;
    await pool.query('INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
      [userId, injuryId]);
    await pool.query(
      `INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern)
       VALUES (?, ?, 'test')`, [other.exercise_id, injuryId],
    );

    const ctx = await loadSwapContext(pool, userId, planExerciseId);
    const rows = await listAlternatives(pool, ctx, { q: null, limit: 20 });

    assert.ok(!rows.some((r) => r.exerciseId === other.exercise_id),
      'the injury filter is the safety claim; alternatives must honour it');
  });

  await t.test('search keeps the injury filter while dropping the muscle filter', async () => {
    const planExerciseId = await reset();
    const [inj] = await pool.query('SELECT injury_id FROM injuries LIMIT 1');
    await pool.query('INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
      [userId, inj[0].injury_id]);
    await pool.query(
      `INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern)
       VALUES (?, ?, 'test')`, [other.exercise_id, inj[0].injury_id],
    );

    const ctx = await loadSwapContext(pool, userId, planExerciseId);
    const rows = await listAlternatives(pool, ctx, { q: other.name, limit: 20 });

    assert.ok(!rows.some((r) => r.exerciseId === other.exercise_id),
      'searching by name must not route around the injury filter');
  });

  await t.test('swapping keeps the prescribed volume and slot', async () => {
    const planExerciseId = await reset();
    const ctx = await loadSwapContext(pool, userId, planExerciseId);

    await swapPlanExercise(pool, ctx, other.exercise_id);

    const [rows] = await pool.query(
      'SELECT exercise_id, order_no, target_sets, target_reps FROM plan_exercises WHERE plan_exercise_id = ?',
      [planExerciseId],
    );
    assert.equal(rows[0].exercise_id, other.exercise_id);
    assert.equal(rows[0].order_no, 1, 'the slot in the session must not move');
    assert.equal(rows[0].target_sets, 3, 'volume comes from the goal, not the exercise');
    assert.equal(rows[0].target_reps, '8-12');
  });

  await t.test('refuses an exercise already in the plan', async () => {
    const planExerciseId = await reset();
    const ctx = await loadSwapContext(pool, userId, planExerciseId);

    await assert.rejects(
      () => swapPlanExercise(pool, ctx, inPlan.exercise_id),
      (err) => err.code === 'EXERCISE_NOT_ALLOWED',
      'a duplicate would give the user the same movement twice',
    );
  });

  await t.test('refuses a contraindicated exercise even when asked directly', async () => {
    const planExerciseId = await reset();
    const [inj] = await pool.query('SELECT injury_id FROM injuries LIMIT 1');
    await pool.query('INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
      [userId, inj[0].injury_id]);
    await pool.query(
      `INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern)
       VALUES (?, ?, 'test')`, [other.exercise_id, inj[0].injury_id],
    );
    const ctx = await loadSwapContext(pool, userId, planExerciseId);

    await assert.rejects(
      () => swapPlanExercise(pool, ctx, other.exercise_id),
      (err) => err.code === 'EXERCISE_NOT_ALLOWED',
      'the client list is a suggestion; the server decides',
    );
  });

  // Deliberately last and does its own setup rather than calling reset():
  // reset() always builds its plan on `abs` (see the diagnostic in the task
  // report), and every live `abs` exercise in the fixture is body weight, so
  // a bodyweightOnly assertion there cannot tell "filter implemented" apart
  // from "filter absent" -- the pre-existing ownership clause already
  // restricts everything to body weight when nothing else is owned.
  // `biceps` is the only muscle group in the fixture with a non-bodyweight
  // live strength exercise, so this subtest plants its plan there instead.
  //
  // Every other subtest in this file starts with reset(), whose unscoped
  // DELETEs wipe plan_exercises/workout_plans/user_equipment/users
  // regardless of what came before -- so nothing here can leak into an
  // earlier-running subtest. Keeping this one last means nothing runs after
  // it either, so no cleanup beyond dropAllTables (already run in t.after)
  // is needed.
  await t.test('bodyweightOnly excludes equipment the user owns', async () => {
    await pool.query('DELETE FROM plan_exercises');
    await pool.query('DELETE FROM workout_plans');
    await pool.query('DELETE FROM user_equipment');
    await pool.query('DELETE FROM user_injuries');
    await pool.query('DELETE FROM exercise_contraindications');
    await pool.query('DELETE FROM users');

    const [ins] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('bw@example.com','x','B')",
    );
    const bwUserId = ins.insertId;

    // Two biceps exercises: one to sit in the plan, one non-bodyweight to be
    // offered as an alternative. The plan exercise's own equipment does not
    // matter -- loadSwapContext only reads its muscle group.
    const [bicepsRows] = await pool.query(
      `SELECT x.exercise_id, x.name, eq.name AS equip,
              COALESCE(eq.parent_equipment_id, eq.equipment_id) AS owned_id
         FROM exercises x
         JOIN equipment eq ON eq.equipment_id = x.equipment_id
         LEFT JOIN exercise_categories cat ON cat.exercise_id = x.exercise_id
        WHERE x.status = 'live'
          AND COALESCE(cat.category,'strength') = 'strength'
          AND x.muscle_group = 'biceps'
        ORDER BY x.exercise_id`,
    );
    assert.ok(
      bicepsRows.length >= 2 && bicepsRows.some((r) => r.equip !== 'body weight'),
      'fixture must carry two live biceps exercises with a non-bodyweight one to test against',
    );
    const kit = bicepsRows.find((r) => r.equip !== 'body weight');
    const inPlanRow = bicepsRows.find((r) => r.exercise_id !== kit.exercise_id);

    // Inserted directly rather than through savePlan: both fixture biceps
    // rows are literally named "Shared Name", and savePlan/resolveExerciseIds
    // resolves a name to its lowest live exercise_id -- with this fixture it
    // would silently plant `kit` in the plan instead of `inPlanRow` no matter
    // which of the two names is passed, since they are identical strings.
    const [planResult] = await pool.query(
      `INSERT INTO workout_plans
         (user_id, name, split_style, days_per_week, session_length_min, week_no, is_active)
       VALUES (?, 'P', 'full_body', 3, 45, 1, TRUE)`,
      [bwUserId],
    );
    await pool.query(
      `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps)
       VALUES (?, ?, 1, 3, '8-12')`,
      [planResult.insertId, inPlanRow.exercise_id],
    );

    // Own the equipment the alternative needs -- the COALESCE'd parent id is
    // what the ownership clause compares against.
    await pool.query(
      'INSERT INTO user_equipment (user_id, equipment_id) VALUES (?, ?)',
      [bwUserId, kit.owned_id],
    );

    const plan = await getActivePlan(pool, bwUserId);
    const ctx = await loadSwapContext(pool, bwUserId, plan.exercises[0].planExerciseId);

    const unfiltered = await listAlternatives(pool, ctx, { q: null, limit: 50 });
    assert.ok(unfiltered.some((r) => r.exerciseId === kit.exercise_id),
      'without this the filtered assertion below passes whether or not the filter exists');

    const filtered = await listAlternatives(pool, ctx, { q: null, limit: 50, bodyweightOnly: true });
    assert.ok(!filtered.some((r) => r.exerciseId === kit.exercise_id),
      'a user filtering for bodyweight must not be offered equipment work');
    for (const row of filtered) {
      const [check] = await pool.query(
        `SELECT eq.name FROM exercises x
           JOIN equipment eq ON eq.equipment_id = x.equipment_id
          WHERE x.exercise_id = ?`, [row.exerciseId],
      );
      assert.equal(check[0].name, 'body weight',
        'a user filtering for bodyweight cannot be offered a barbell lift');
    }
  });
});
