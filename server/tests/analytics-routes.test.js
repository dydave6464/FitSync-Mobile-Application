'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('analytics routes', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const res = await request(app).post('/api/v1/auth/register')
    .send({ email: 'an@example.com', password: 's3cret-pass', fullName: 'A' })
    .expect(201);
  await markEmailVerified(pool, res.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'an@example.com', password: 's3cret-pass' }).expect(200);
  const auth = { Authorization: `Bearer ${login.body.data.token}` };

  await t.test('requires a token', async () => {
    await request(app).get('/api/v1/sessions/analytics').expect(401);
  });

  await t.test('an unknown period is a 400', async () => {
    await request(app).get('/api/v1/sessions/analytics?period=decade')
      .set(auth).expect(400);
  });

  // Every reader here signals "unknown period" by returning null, which the
  // route turns into the 400 above. A bare SUMMARY_WINDOWS[period] lookup
  // reads 'constructor' off the prototype chain instead and returns a
  // function, so the null never happens and the query throws a 500.
  await t.test('a prototype property is a 400, not a 500', async () => {
    for (const period of ['constructor', 'toString', '__proto__']) {
      await request(app).get(`/api/v1/sessions/analytics?period=${period}`)
        .set(auth).expect(400);
    }
  });

  await t.test('a brand new account gets a full, empty line', async () => {
    const get = await request(app).get('/api/v1/sessions/analytics?period=week')
      .set(auth).expect(200);

    assert.equal(get.body.data.period, 'week');
    assert.equal(get.body.data.volume.length, 7, 'never an empty chart');
    assert.ok(get.body.data.volume.every((b) => b.volumeKg === 0));
    assert.equal(get.body.data.adherence.done, 0);
    assert.equal(get.body.data.adherence.target, null);
    assert.equal(get.body.data.change.changePct, null, 'nothing to compare against yet');
    assert.deepEqual(get.body.data.muscles, []);
  });

  await t.test('the default period is week', async () => {
    const get = await request(app).get('/api/v1/sessions/analytics')
      .set(auth).expect(200);
    assert.equal(get.body.data.period, 'week');
  });
});
