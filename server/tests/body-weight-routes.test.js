'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('body weight routes', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const res = await request(app).post('/api/v1/auth/register')
    .send({ email: 'bw@example.com', password: 's3cret-pass', fullName: 'W' })
    .expect(201);
  await markEmailVerified(pool, res.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'bw@example.com', password: 's3cret-pass' }).expect(200);
  const auth = { Authorization: `Bearer ${login.body.data.token}` };

  await t.test('requires a token', async () => {
    await request(app).get('/api/v1/profile/body-weight').expect(401);
  });

  await t.test('an unknown period is a 400', async () => {
    await request(app).get('/api/v1/profile/body-weight?period=decade')
      .set(auth).expect(400);
  });

  await t.test('posting an entry returns it', async () => {
    const post = await request(app).post('/api/v1/profile/body-weight')
      .set(auth).send({ weightKg: 71.4 }).expect(201);
    assert.equal(post.body.data.weightKg, 71.4);
    assert.match(post.body.data.loggedOn, /^\d{4}-\d{2}-\d{2}$/);
  });

  await t.test('and it appears in the series with the unit', async () => {
    const get = await request(app).get('/api/v1/profile/body-weight?period=week')
      .set(auth).expect(200);
    assert.equal(get.body.data.points.length, 1);
    assert.equal(get.body.data.points[0].weightKg, 71.4);
    assert.equal(get.body.data.unit, 'kg');
  });

  await t.test('the reference falls back to the starting weight', async () => {
    const get = await request(app).get('/api/v1/profile/body-weight?period=week')
      .set(auth).expect(200);
    assert.deepEqual(get.body.data.reference, { kind: 'start', weightKg: 71.4 });
  });

  await t.test('a nonsense weight is a 400, not a stored row', async () => {
    await request(app).post('/api/v1/profile/body-weight')
      .set(auth).send({ weightKg: 714 }).expect(400);
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM body_weight_logs');
    assert.equal(Number(rows[0].n), 1, 'still just the good one');
  });

  await t.test('a missing weight is a 400', async () => {
    await request(app).post('/api/v1/profile/body-weight')
      .set(auth).send({}).expect(400);
  });
});
