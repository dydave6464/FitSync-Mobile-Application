'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const stub = require('../src/services/ml/stub');

test('GET /plans/defaults', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const seen = [];
  let fail = false;
  const ml = {
    planParameters: async (profile) => {
      seen.push(profile);
      if (fail) throw new Error('ML service /plan-parameters responded 500');
      return stub.planParameters(profile);
    },
  };
  const app = buildTestApp({ pool, ml });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const res = await request(app).post('/api/v1/auth/register')
    .send({ email: 'd@example.com', password: 's3cret-pass', fullName: 'D' }).expect(201);
  await markEmailVerified(pool, res.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'd@example.com', password: 's3cret-pass' }).expect(200);
  const auth = `Bearer ${login.body.data.token}`;

  await t.test('answers the length Auto would use, from the stored profile', async () => {
    await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ mainGoal: 'build_muscle', fitnessLevel: 'intermediate' }).expect(200);
    const body = (await request(app).get('/api/v1/plans/defaults')
      .set('Authorization', auth).expect(200)).body;
    assert.deepEqual(body.data, { sessionLengthMin: 60, exercisesPerDay: 8, lengthReason: 'goal' });
    assert.equal(seen.at(-1).mainGoal, 'build_muscle');
    assert.equal(seen.at(-1).overrides, undefined);
  });

  await t.test('an ML failure answers through the normal error path', async () => {
    fail = true;
    const r = await request(app).get('/api/v1/plans/defaults').set('Authorization', auth);
    fail = false;
    assert.equal(r.status, 500);
  });

  await t.test('needs a signed-in user', async () => {
    await request(app).get('/api/v1/plans/defaults').expect(401);
  });
});
