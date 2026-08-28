'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
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
    auth = `Bearer ${res.body.data.token}`;
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

  await t.test('a failed generation leaves onboarding incomplete', async () => {
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
  });
});
