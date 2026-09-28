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

test('activity endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `act${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'A' }).expect(201);
    const { userId } = res.body.data.user;
    await markEmailVerified(pool, userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { userId, token: login.body.data.token };
  };
  const setBody = (userId, heightCm, weightKg) => pool.query(
    'UPDATE users SET height_cm = ?, weight_kg = ?, sex = NULL WHERE user_id = ?',
    [heightCm, weightKg, userId],
  );
  const put = (token, date, payload) => request(app).put(`/api/v1/activity/${date}`)
    .set('Authorization', `Bearer ${token}`).send(payload);
  const get = (token) => request(app).get('/api/v1/activity')
    .set('Authorization', `Bearer ${token}`);
  const today = manilaDay();

  await t.test('both endpoints require sign-in', async () => {
    await request(app).get('/api/v1/activity').expect(401);
    await request(app).put(`/api/v1/activity/${today}`).send({ steps: 1 }).expect(401);
  });

  await t.test('a day is saved with its estimates', async () => {
    const { userId, token } = await freshUser();
    await setBody(userId, 170, 70);
    const res = await put(token, today, { steps: 6420 }).expect(200);
    assert.deepEqual(res.body.data, {
      date: today, steps: 6420, caloriesBurned: 158, distanceKm: 4.52,
      activeMinutes: 64, missing: [],
    });
  });

  await t.test('without height or weight the estimates are 0 and named missing', async () => {
    const { token } = await freshUser();
    const res = await put(token, today, { steps: 6420 }).expect(200);
    assert.deepEqual(res.body.data, {
      date: today, steps: 6420, caloriesBurned: 0, distanceKm: 0,
      activeMinutes: 64, missing: ['height', 'weight'],
    });
  });

  await t.test('a later save recomputes with the current profile', async () => {
    const { userId, token } = await freshUser();
    await put(token, today, { steps: 6420 }).expect(200);
    await setBody(userId, 170, 70);
    const res = await put(token, today, { steps: 6420 }).expect(200);
    assert.equal(res.body.data.caloriesBurned, 158);
    assert.deepEqual(res.body.data.missing, []);
  });

  await t.test('a lower count never replaces a higher one', async () => {
    const { token } = await freshUser();
    await put(token, today, { steps: 5000 }).expect(200);
    const res = await put(token, today, { steps: 3000 }).expect(200);
    assert.equal(res.body.data.steps, 5000);
  });

  await t.test('two saves at once keep the higher count', async () => {
    const { token } = await freshUser();
    const [a, b] = await Promise.all([
      put(token, today, { steps: 4000 }), put(token, today, { steps: 7000 }),
    ]);
    assert.equal(a.status, 200);
    assert.equal(b.status, 200);
    const week = await get(token).expect(200);
    assert.equal(week.body.data.days[6].steps, 7000);
  });

  await t.test('today and six days back are accepted; seven back and tomorrow are not', async () => {
    const { token } = await freshUser();
    await put(token, manilaDay(6), { steps: 10 }).expect(200);
    const old = await put(token, manilaDay(7), { steps: 10 }).expect(400);
    assert.equal(old.body.error.code, 'DATE_OUT_OF_RANGE');
    const future = await put(token, manilaDay(-1), { steps: 10 }).expect(400);
    assert.equal(future.body.error.code, 'DATE_OUT_OF_RANGE');
  });

  await t.test('a date that is not a real day is refused', async () => {
    const { token } = await freshUser();
    for (const bad of ['abc', '2026-02-30', '2026-13-01', '2026-9-1']) {
      const res = await put(token, bad, { steps: 10 }).expect(400);
      assert.equal(res.body.error.code, 'DATE_INVALID', bad);
    }
  });

  await t.test('steps must be a whole number from 0 to 100000', async () => {
    const { token } = await freshUser();
    for (const bad of [-1, 100001, 12.5, '100', null, undefined]) {
      const res = await put(token, today, { steps: bad }).expect(400);
      assert.equal(res.body.error.code, 'STEPS_INVALID', String(bad));
    }
    await put(token, today, { steps: 0 }).expect(200);
    await put(token, today, { steps: 100000 }).expect(200);
  });

  await t.test('the week is seven days, oldest first, empty days null', async () => {
    const { token } = await freshUser();
    await put(token, manilaDay(2), { steps: 3000 }).expect(200);
    const res = await get(token).expect(200);
    const { days } = res.body.data;
    assert.equal(days.length, 7);
    assert.equal(days[0].date, manilaDay(6));
    assert.equal(days[6].date, today);
    assert.equal(days[4].date, manilaDay(2));
    assert.equal(days[4].steps, 3000);
    assert.deepEqual(days[5], {
      date: manilaDay(1), steps: null, caloriesBurned: null, distanceKm: null, activeMinutes: null,
    });
  });

  await t.test('usual needs three earlier days, and today never counts', async () => {
    const { token } = await freshUser();
    await put(token, manilaDay(1), { steps: 3000 }).expect(200);
    await put(token, manilaDay(2), { steps: 4000 }).expect(200);
    await put(token, today, { steps: 9000 }).expect(200);
    let res = await get(token).expect(200);
    assert.equal(res.body.data.usual, null);
    assert.equal(res.body.data.usualDays, 2);

    await put(token, manilaDay(3), { steps: 5000 }).expect(200);
    res = await get(token).expect(200);
    assert.equal(res.body.data.usual, 4000);
    assert.equal(res.body.data.usualDays, 3);
  });

  await t.test('missing follows the current profile', async () => {
    const { userId, token } = await freshUser();
    assert.deepEqual((await get(token).expect(200)).body.data.missing, ['height', 'weight']);
    await setBody(userId, 170, null);
    assert.deepEqual((await get(token).expect(200)).body.data.missing, ['weight']);
  });

  await t.test("one user never sees another's days", async () => {
    const a = await freshUser();
    const b = await freshUser();
    await put(a.token, today, { steps: 1234 }).expect(200);
    const res = await get(b.token).expect(200);
    assert.equal(res.body.data.days[6].steps, null);
  });
});
