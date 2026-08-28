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

  await t.test('rolls back entirely when an exercise cannot be resolved', async () => {
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
});
