'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { resolveExerciseIds, savePlan, getActivePlan } = require('../src/db/plans');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('plan persistence', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  let userId;
  const reset = async () => {
    await pool.query('DELETE FROM plan_exercises');
    await pool.query('DELETE FROM workout_plans');
    await pool.query('DELETE FROM users');
    const [r] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('w@example.com','x','W')",
    );
    userId = r.insertId;
  };

  // Names taken from the fixture so this test does not depend on the real
  // catalogue. Read one out rather than hard-coding it.
  let known;
  await t.test('resolves a known name case-insensitively', async () => {
    const [rows] = await pool.query("SELECT name FROM exercises WHERE status='live' LIMIT 1");
    known = rows[0].name;
    const map = await resolveExerciseIds(pool, [known.toUpperCase()]);
    assert.ok(map.get(known.toUpperCase()), 'matching must ignore case');
  });

  await t.test('reports a name it cannot resolve rather than guessing', async () => {
    const map = await resolveExerciseIds(pool, ['Definitely Not An Exercise']);
    assert.equal(map.get('Definitely Not An Exercise'), undefined);
  });

  // The fixture's "Shared Name" (source_id 0003 and 0004) seeds as two
  // distinct live rows with the same name — a real condition, not a
  // contrived one: the earlier catalogue slice recorded six duplicate names
  // in the live data, which is why the catalogue's own paginated query
  // (src/db/exercises.js) already tiebreaks on exercise_id. Without the same
  // tiebreak here, which row a duplicate name resolves to is whatever order
  // MySQL happens to return, so two users onboarding with the same generated
  // plan name could silently get different exercises.
  await t.test('resolves a duplicate name to the same (lowest) exercise_id every time', async () => {
    const [dupRows] = await pool.query(
      "SELECT exercise_id FROM exercises WHERE status='live' AND name = 'Shared Name' ORDER BY exercise_id",
    );
    assert.ok(dupRows.length >= 2, 'fixture must contain a duplicate live name to exercise this');
    const expectedId = dupRows[0].exercise_id;

    const map = await resolveExerciseIds(pool, ['Shared Name']);
    assert.equal(map.get('Shared Name'), expectedId);
  });

  await t.test('saves a plan and its exercises', async () => {
    await reset();
    const planId = await savePlan(pool, userId, {
      name: 'Starter Plan',
      splitStyle: 'full_body',
      daysPerWeek: 3,
      sessionLengthMin: 45,
      weekNo: 1,
      exercises: [{ name: known, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
    });
    assert.ok(planId);
    const plan = await getActivePlan(pool, userId);
    assert.equal(plan.name, 'Starter Plan');
    assert.equal(plan.exercises.length, 1);
    assert.equal(plan.exercises[0].targetReps, '8-12');
  });

  // This proves the pre-transaction guard: resolution fails before
  // pool.getConnection() is ever called, so no transaction opens and
  // conn.rollback() never runs. See the next test for that.
  await t.test('refuses to write any row when an exercise cannot be resolved', async () => {
    await reset();
    await assert.rejects(() => savePlan(pool, userId, {
      name: 'Broken Plan',
      splitStyle: 'full_body',
      daysPerWeek: 3,
      sessionLengthMin: 45,
      weekNo: 1,
      exercises: [
        { name: known, orderNo: 1, targetSets: 3, targetReps: '8-12' },
        { name: 'Definitely Not An Exercise', orderNo: 2, targetSets: 3, targetReps: '8-12' },
      ],
    }), (err) => err.code === 'PLAN_GENERATION_FAILED');

    const [plans] = await pool.query('SELECT COUNT(*) AS n FROM workout_plans');
    assert.equal(plans[0].n, 0, 'a half-written plan is worse than none');
  });

  // Unlike the test above, every name here resolves, so savePlan proceeds
  // past the guard and opens a real transaction. The second exercise's null
  // targetReps violates plan_exercises.target_reps NOT NULL only once
  // inside the loop — after the workout_plans row and the first
  // plan_exercises row already exist — so this is the test that actually
  // reaches and exercises conn.rollback().
  await t.test('rolls back a partially inserted plan when a later insert violates a constraint', async () => {
    await reset();
    await assert.rejects(() => savePlan(pool, userId, {
      name: 'Constraint Violation Plan',
      splitStyle: 'full_body',
      daysPerWeek: 3,
      sessionLengthMin: 45,
      weekNo: 1,
      exercises: [
        { name: known, orderNo: 1, targetSets: 3, targetReps: '8-12' },
        { name: known, orderNo: 2, targetSets: 3, targetReps: null },
      ],
    }));

    const [plans] = await pool.query('SELECT COUNT(*) AS n FROM workout_plans');
    assert.equal(plans[0].n, 0, 'the workout_plans row must not survive a later failure in the loop');
    const [exercises] = await pool.query('SELECT COUNT(*) AS n FROM plan_exercises');
    assert.equal(exercises[0].n, 0, 'the first successful plan_exercises insert must not survive either');
  });

  await t.test('only the newest plan is active', async () => {
    await reset();
    const base = {
      splitStyle: 'full_body', daysPerWeek: 3, sessionLengthMin: 45, weekNo: 1,
      exercises: [{ name: known, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
    };
    await savePlan(pool, userId, { ...base, name: 'First' });
    await savePlan(pool, userId, { ...base, name: 'Second' });
    assert.equal((await getActivePlan(pool, userId)).name, 'Second');
    const [active] = await pool.query(
      'SELECT COUNT(*) AS n FROM workout_plans WHERE user_id = ? AND is_active = TRUE', [userId],
    );
    assert.equal(active[0].n, 1);
  });

  await t.test('the active plan addresses each row by plan_exercise_id', async () => {
    await reset();
    await savePlan(pool, userId, {
      name: 'P', splitStyle: 'full_body', daysPerWeek: 3, sessionLengthMin: 45, weekNo: 1,
      exercises: [{ name: known, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
    });

    const plan = await getActivePlan(pool, userId);
    const [rows] = await pool.query(
      'SELECT plan_exercise_id FROM plan_exercises WHERE plan_id = ?', [plan.planId],
    );

    assert.equal(plan.exercises[0].planExerciseId, rows[0].plan_exercise_id,
      'without this the client cannot name the row it wants to swap');
  });
});
