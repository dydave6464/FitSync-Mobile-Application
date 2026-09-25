'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const { manilaDay } = require('../src/lib/manila-day');

test('calendar endpoint', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `cal${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'C' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { Authorization: `Bearer ${login.body.data.token}` };
  };

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/calendar')
      .query({ from: '2026-09-01', to: '2026-09-02' }).expect(401);
  });

  await t.test('yesterday, today and tomorrow, with a habit due and then ticked', async () => {
    const auth = await freshUser();
    const { habitId } = (await request(app).post('/api/v1/routine/habits').set(auth)
      .send({ title: 'Stretch', time: '06:30', weekdays: [1, 2, 3, 4, 5, 6, 7] })
      .expect(201)).body.data.habit;
    const yesterday = manilaDay(1);
    const today = manilaDay(0);
    const tomorrow = manilaDay(-1);
    const get = async () => (await request(app).get('/api/v1/calendar').set(auth)
      .query({ from: yesterday, to: tomorrow }).expect(200)).body.data;

    let cal = await get();
    assert.equal(cal.today, today);
    assert.deepEqual(cal.days.map((d) => d.date), [yesterday, today, tomorrow]);
    assert.deepEqual(cal.days[0], { date: yesterday, workout: null, habits: [] },
      'nothing was done yesterday');
    assert.deepEqual(cal.days[1].habits,
      [{ habitId, title: 'Stretch', time: '06:30', done: false }]);
    assert.deepEqual(cal.days[2].habits,
      [{ habitId, title: 'Stretch', time: '06:30', done: false }]);

    await request(app).put(`/api/v1/routine/habits/${habitId}/check`).set(auth).expect(200);
    cal = await get();
    assert.equal(cal.days[1].habits[0].done, true);
    assert.equal(cal.days[2].habits[0].done, false);
  });

  await t.test('62 days is the most one request covers', async () => {
    const res = await request(app).get('/api/v1/calendar').set(await freshUser())
      .query({ from: '2026-01-01', to: '2026-03-03' }).expect(200);
    assert.equal(res.body.data.days.length, 62);
  });

  await t.test('refuses a range it cannot read', async () => {
    const auth = await freshUser();
    const cases = [
      [{ to: '2026-09-02' }, 'from missing'],
      [{ from: '2026-09-01' }, 'to missing'],
      [{ from: '2026-9-01', to: '2026-09-02' }, 'not zero-padded'],
      [{ from: 'yesterday', to: '2026-09-02' }, 'not a date'],
      [{ from: '2026-02-30', to: '2026-03-02' }, 'no such day'],
      [{ from: '2026-13-01', to: '2026-13-02' }, 'no such month'],
      [{ from: '2026-09-03', to: '2026-09-02' }, 'from after to'],
      [{ from: '2026-01-01', to: '2026-03-04' }, '63 days'],
    ];
    for (const [query, why] of cases) {
      const res = await request(app).get('/api/v1/calendar').set(auth).query(query);
      assert.equal(res.status, 400, why);
      assert.equal(res.body.error.code, 'DATE_RANGE_INVALID', why);
    }
  });
});
