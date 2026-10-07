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
const { toPlanPayload } = require('../src/services/ml/profile-payload');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

// health-check-routes.test.js builds its app with buildTestApp({ pool }) --
// no ml dep, so complete-onboarding would 500 there. This file builds its
// own app with a capturing fake ml instead, to prove what getProfile hands
// the generator once a health check is stored.
test('a stored health caution reaches the plan generator', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  const [live] = await pool.query("SELECT name FROM exercises WHERE status='live' LIMIT 1");
  const known = live[0].name;

  // Records every profile handed to generatePlan, then returns a plan
  // shaped like stub.js's output -- one known exercise is enough since this
  // test is about what reaches the generator, not the plan's shape.
  const recorded = [];
  const ml = {
    generatePlan: async (profile) => {
      recorded.push(profile);
      return {
        name: 'Starter Plan',
        splitStyle: 'full_body',
        daysPerWeek: 3,
        sessionLengthMin: 45,
        weekNo: 1,
        exercises: [{ name: known, dayNo: 1, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
      };
    },
    estimateInjuryRisk: async () => ({ riskLevel: 'low', trainingLoadScore: 0 }),
  };
  const app = buildTestApp({ pool, ml });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `hcp${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'HCP' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      put: (b) => request(app).put('/api/v1/profile/health').set(auth).send(b),
      complete: () => request(app).post('/api/v1/profile/complete-onboarding').set(auth),
    };
  };

  await t.test('a stored positive check marks the profile the generator receives', async () => {
    const u = await freshUser();
    await u.put({
      conditions: [],
      chestPain: false,
      dizziness: false,
      supervisedOnly: true,
      consent: true,
      acknowledged: true,
    }).expect(200);

    await u.complete().expect(200);

    const sent = recorded.at(-1);
    assert.equal(sent.healthCaution, true);
    const payload = toPlanPayload(sent);
    assert.equal(payload.healthCaution, true);
    assert.equal(payload.conditions, undefined);
  });

  await t.test('no stored row means no caution reaches the generator', async () => {
    const u = await freshUser();

    await u.complete().expect(200);

    const sent = recorded.at(-1);
    assert.equal(sent.healthCaution, false);
    const payload = toPlanPayload(sent);
    assert.equal(payload.healthCaution, false);
    assert.equal(payload.conditions, undefined);
  });
});
