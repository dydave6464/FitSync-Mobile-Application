'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { seedInjuries } = require('../src/db/seed-injuries');
const { savePlan, getActivePlan } = require('../src/db/plans');
const { loadSwapContext, listAlternatives } = require('../src/db/plan-swap');
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
});
