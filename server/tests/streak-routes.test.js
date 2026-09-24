'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('streak endpoint', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `st${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'S' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { Authorization: `Bearer ${login.body.data.token}` };
  };

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/streak').expect(401);
  });

  await t.test('a new account has no streak and a week of seven quiet days', async () => {
    const res = await request(app).get('/api/v1/streak').set(await freshUser()).expect(200);
    const s = res.body.data;
    assert.equal(s.current, 0);
    assert.equal(s.best, 0);
    assert.equal(s.todayActive, false);
    assert.equal(s.week.length, 7);
    for (const day of s.week) {
      assert.match(day.date, /^\d{4}-\d{2}-\d{2}$/);
      assert.equal(day.active, false);
    }
  });

  await t.test('ticking a habit today starts one', async () => {
    const auth = await freshUser();
    const { habitId } = (await request(app).post('/api/v1/routine/habits').set(auth)
      .send({ title: 'Stretch', weekdays: [1, 2, 3, 4, 5, 6, 7] }).expect(201)).body.data.habit;
    await request(app).put(`/api/v1/routine/habits/${habitId}/check`).set(auth).expect(200);

    const s = (await request(app).get('/api/v1/streak').set(auth).expect(200)).body.data;
    assert.equal(s.current, 1);
    assert.equal(s.best, 1);
    assert.equal(s.todayActive, true);
  });
});
