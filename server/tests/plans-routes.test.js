'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { markEmailVerified } = require('../src/db/users');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('plan endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  const [live] = await pool.query("SELECT name FROM exercises WHERE status='live' LIMIT 1");
  const known = live[0].name;

  // A stub whose exercise names exist in the fixture catalogue.
  const ml = {
    generatePlan: async () => ({
      name: 'Starter Plan', splitStyle: 'full_body', daysPerWeek: 3,
      sessionLengthMin: 45, weekNo: 1,
      exercises: [{ name: known, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
    }),
    estimateInjuryRisk: async () => ({ riskLevel: 'low', trainingLoadScore: 0 }),
  };

  const app = buildTestApp({ pool, ml });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  let auth;
  const reset = async () => {
    await pool.query('DELETE FROM plan_exercises');
    await pool.query('DELETE FROM workout_plans');
    await pool.query('DELETE FROM user_identities');
    await pool.query('DELETE FROM users');
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'w@example.com', password: 's3cret-pass', fullName: 'W' }).expect(201);
    // These tests exercise plan endpoints behind requireAuth, not the
    // verification gate itself (that belongs to auth-verification.test.js),
    // so verify the throwaway account directly rather than routing it
    // through the mail flow. Registration alone no longer grants a session,
    // so sign in afterward for a real token.
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'w@example.com', password: 's3cret-pass' }).expect(200);
    auth = `Bearer ${login.body.data.token}`;
  };

  await t.test('completing onboarding generates and returns a plan', async () => {
    await reset();
    const res = await request(app).post('/api/v1/profile/complete-onboarding')
      .set('Authorization', auth).expect(200);
    assert.equal(res.body.data.plan.name, 'Starter Plan');
    assert.equal(res.body.data.plan.exercises.length, 1);
    assert.equal(res.body.data.profile.onboardingCompleted, true);
  });

  await t.test('the active plan is readable afterwards', async () => {
    await reset();
    await request(app).post('/api/v1/profile/complete-onboarding').set('Authorization', auth).expect(200);
    const res = await request(app).get('/api/v1/plans/active').set('Authorization', auth).expect(200);
    assert.equal(res.body.data.plan.exercises[0].targetReps, '8-12');
  });

  await t.test('no plan yet is a null, not a 404', async () => {
    await reset();
    const res = await request(app).get('/api/v1/plans/active').set('Authorization', auth).expect(200);
    assert.equal(res.body.data.plan, null);
  });

  await t.test('a failed generation leaves onboarding incomplete, and retrying succeeds', async () => {
    await reset();
    const brokenApp = buildTestApp({
      pool,
      ml: {
        generatePlan: async () => ({
          name: 'Broken', splitStyle: 'full_body', daysPerWeek: 3, sessionLengthMin: 45, weekNo: 1,
          exercises: [{ name: 'Definitely Not An Exercise', orderNo: 1, targetSets: 3, targetReps: '8-12' }],
        }),
        estimateInjuryRisk: async () => ({ riskLevel: 'low', trainingLoadScore: 0 }),
      },
    });
    const res = await request(brokenApp).post('/api/v1/profile/complete-onboarding')
      .set('Authorization', auth).expect(502);
    assert.equal(res.body.error.code, 'PLAN_GENERATION_FAILED');

    // Stranding a user as "onboarded" with no plan gives them no way back.
    const after = await request(app).get('/api/v1/profile').set('Authorization', auth).expect(200);
    assert.equal(after.body.data.profile.onboardingCompleted, false);

    // onboardingCompleted staying false is only the precondition for
    // recovery, not the property that matters — the user must actually be
    // able to retry and end up with a plan. Same user, same token, this
    // time against the working ML stub.
    const retry = await request(app).post('/api/v1/profile/complete-onboarding')
      .set('Authorization', auth).expect(200);
    assert.equal(retry.body.data.plan.name, 'Starter Plan');
    assert.equal(retry.body.data.profile.onboardingCompleted, true);
  });

  await t.test('resolves each exercise to its curated equipment name', async () => {
    // This test needs a user who already has an active plan, reached the
    // same way the tests above reach it: drive complete-onboarding with the
    // ml stub declared at the top of this file.
    await reset();
    await request(app).post('/api/v1/profile/complete-onboarding')
      .set('Authorization', auth).expect(200);

    // The catalogue tags an exercise with a raw name like 'cable'. Curation
    // makes that row a hidden child of 'Machines'. The plan must report the
    // curated parent, because that is what the client's MET table keys on.
    const [rows] = await pool.query(
      `SELECT x.exercise_id, e.name AS raw FROM exercises x
         JOIN equipment e ON e.equipment_id = x.equipment_id
        WHERE x.status = 'live' LIMIT 1`,
    );
    const raw = rows[0];

    // This test mutates a real catalogue row (the one at `raw.raw`) to
    // simulate curation having adopted it. Captured here so the finally
    // block below can put it back — otherwise this row stays reparented to
    // a fake 'planmet' equipment row forever, and whatever test happens to
    // be appended after this one in the file inherits a corrupted fixture
    // instead of the pristine one it expects.
    const [[originalRow]] = await pool.query(
      'SELECT display_name, display_order, is_user_selectable, parent_equipment_id '
      + 'FROM equipment WHERE name = ?',
      [raw.raw],
    );

    try {
      await pool.query(
        "INSERT IGNORE INTO equipment (name, display_name, display_order, "
        + "is_user_selectable) VALUES ('planmet', 'PlanMet', 99, 1)",
      );
      const [[parent]] = await pool.query(
        "SELECT equipment_id FROM equipment WHERE name = 'planmet'",
      );

      await pool.query(
        'UPDATE equipment SET parent_equipment_id = ?, is_user_selectable = 0, '
        + 'display_name = NULL WHERE name = ?',
        [parent.equipment_id, raw.raw],
      );

      const res = await request(app).get('/api/v1/plans/active')
        .set('Authorization', auth).expect(200);
      const names = res.body.data.plan.exercises.map((e) => e.equipment);
      assert.ok(names.includes('PlanMet'),
        'an adopted child must report its curated parent, not its raw tag');
    } finally {
      await pool.query(
        'UPDATE equipment SET display_name = ?, display_order = ?, '
        + 'is_user_selectable = ?, parent_equipment_id = ? WHERE name = ?',
        [
          originalRow.display_name, originalRow.display_order,
          originalRow.is_user_selectable, originalRow.parent_equipment_id,
          raw.raw,
        ],
      );
      // No FK reference is left pointing at it once the row above is
      // un-parented, so this can simply be removed rather than restored.
      await pool.query("DELETE FROM equipment WHERE name = 'planmet'");
    }

    // Proves the finally block actually put the row back, rather than
    // merely running without throwing.
    const [[restoredRow]] = await pool.query(
      'SELECT display_name, display_order, is_user_selectable, parent_equipment_id '
      + 'FROM equipment WHERE name = ?',
      [raw.raw],
    );
    assert.deepEqual(restoredRow, originalRow,
      'the mutated catalogue row must be restored for whatever test runs next');
    const [[planmet]] = await pool.query(
      "SELECT COUNT(*) AS n FROM equipment WHERE name = 'planmet'",
    );
    assert.equal(planmet.n, 0, 'the fixture equipment row must not leak');
  });

  await t.test('alternatives require the caller to own the plan', async () => {
    await reset();
    await request(app).post('/api/v1/profile/complete-onboarding').set('Authorization', auth).expect(200);
    const mine = await request(app).get('/api/v1/plans/active').set('Authorization', auth).expect(200);
    const planExerciseId = mine.body.data.plan.exercises[0].planExerciseId;

    // A second account must not reach the first account's row.
    await request(app).post('/api/v1/auth/register')
      .send({ email: 'intruder@example.com', password: 's3cret-pass', fullName: 'I' }).expect(201);
    const [u] = await pool.query("SELECT user_id FROM users WHERE email='intruder@example.com'");
    await markEmailVerified(pool, u[0].user_id);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'intruder@example.com', password: 's3cret-pass' }).expect(200);

    await request(app)
      .get(`/api/v1/plans/exercises/${planExerciseId}/alternatives`)
      .set('Authorization', `Bearer ${login.body.data.token}`)
      .expect(404);

    // Spec §4's first PATCH validation rule is what makes this a route
    // rather than an IDOR: without it, any authenticated user could rewrite
    // any other user's plan row by guessing a plan_exercise_id.
    await request(app)
      .patch(`/api/v1/plans/exercises/${planExerciseId}`)
      .set('Authorization', `Bearer ${login.body.data.token}`)
      .send({ exerciseId: 1 })
      .expect(404);
  });

  await t.test('a swap returns the updated plan', async () => {
    await reset();
    await request(app).post('/api/v1/profile/complete-onboarding').set('Authorization', auth).expect(200);
    const before = await request(app).get('/api/v1/plans/active').set('Authorization', auth).expect(200);
    const row = before.body.data.plan.exercises[0];

    const alts = await request(app)
      .get(`/api/v1/plans/exercises/${row.planExerciseId}/alternatives`)
      .set('Authorization', auth).expect(200);

    const target = alts.body.data.alternatives[0];
    const res = await request(app)
      .patch(`/api/v1/plans/exercises/${row.planExerciseId}`)
      .set('Authorization', auth).send({ exerciseId: target.exerciseId }).expect(200);

    const swapped = res.body.data.plan.exercises
      .find((e) => e.planExerciseId === row.planExerciseId);
    assert.equal(swapped.exerciseId, target.exerciseId);
    assert.equal(swapped.targetSets, row.targetSets, 'volume survives the swap');
  });

  await t.test('a rejected target answers 400, not 500', async () => {
    await reset();
    await request(app).post('/api/v1/profile/complete-onboarding').set('Authorization', auth).expect(200);
    const before = await request(app).get('/api/v1/plans/active').set('Authorization', auth).expect(200);
    const row = before.body.data.plan.exercises[0];

    await request(app)
      .patch(`/api/v1/plans/exercises/${row.planExerciseId}`)
      .set('Authorization', auth)
      .send({ exerciseId: row.exerciseId })   // already in the plan
      .expect(400);
  });

  await t.test('a malformed plan exercise id is a 404, not a 500', async () => {
    await reset();
    await request(app)
      .get('/api/v1/plans/exercises/abc/alternatives')
      .set('Authorization', auth)
      .expect(404);

    await request(app)
      .patch('/api/v1/plans/exercises/abc')
      .set('Authorization', auth)
      .send({ exerciseId: 1 })
      .expect(404);
  });
});
