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
  const putBatch = (token, payload) => request(app).put('/api/v1/activity')
    .set('Authorization', `Bearer ${token}`).send(payload);
  const savedRows = async (userId) => {
    const [[{ n }]] = await pool.query(
      'SELECT COUNT(*) AS n FROM activity_logs WHERE user_id = ?', [userId],
    );
    return n;
  };
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
    assert.equal(old.body.error.message, 'Steps can be saved for today and the six days before it.');
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

  await t.test('the week carries the per-step factors of the current profile', async () => {
    const near = (actual, expected) => assert.ok(
      Math.abs(actual - expected) < 1e-12, `${actual} is not ${expected}`,
    );
    const { userId, token } = await freshUser();
    await setBody(userId, 170, 70);
    let { perStep } = (await get(token).expect(200)).body.data;
    near(perStep.distanceKm, 0.00070380);
    near(perStep.caloriesBurned, 0.024633);
    assert.equal(perStep.activeMinutes, 0.01);

    await setBody(userId, null, 70);
    ({ perStep } = (await get(token).expect(200)).body.data);
    assert.deepEqual(perStep, { distanceKm: null, caloriesBurned: null, activeMinutes: 0.01 });

    await setBody(userId, 170, null);
    ({ perStep } = (await get(token).expect(200)).body.data);
    near(perStep.distanceKm, 0.00070380);
    assert.equal(perStep.caloriesBurned, null);
  });

  await t.test('the batch requires sign-in', async () => {
    await request(app).put('/api/v1/activity')
      .send({ days: [{ date: today, steps: 1 }] }).expect(401);
  });

  await t.test('a batch saves several days and answers the week', async () => {
    const { userId, token } = await freshUser();
    await setBody(userId, 170, 70);
    const res = await putBatch(token, {
      days: [
        { date: today, steps: 6420 },
        { date: manilaDay(3), steps: 6420 },
        { date: manilaDay(1), steps: 6420 },
      ],
    }).expect(200);
    const week = res.body.data;
    assert.equal(week.days.length, 7);
    const estimated = {
      steps: 6420, caloriesBurned: 158, distanceKm: 4.52, activeMinutes: 64,
    };
    assert.deepEqual(week.days[6], { date: today, ...estimated });
    assert.deepEqual(week.days[5], { date: manilaDay(1), ...estimated });
    assert.deepEqual(week.days[3], { date: manilaDay(3), ...estimated });
    assert.equal(week.days[4].steps, null);
    assert.deepEqual(week.skipped, []);
    assert.deepEqual(week.missing, []);
    assert.equal(week.usualDays, 2);
    assert.equal(week.perStep.activeMinutes, 0.01);
    assert.ok(Math.abs(week.perStep.caloriesBurned - 0.024633) < 1e-12);
    // The same week GET answers, plus what was skipped.
    const { skipped, ...rest } = week;
    assert.deepEqual(rest, (await get(token).expect(200)).body.data);
  });

  await t.test('a batch never lowers a day', async () => {
    const { token } = await freshUser();
    await put(token, manilaDay(2), { steps: 8000 }).expect(200);
    const res = await putBatch(token, { days: [{ date: manilaDay(2), steps: 5000 }] }).expect(200);
    assert.equal(res.body.data.days[4].steps, 8000);
  });

  await t.test('days outside the window are skipped and listed; the rest are saved', async () => {
    const { userId, token } = await freshUser();
    const res = await putBatch(token, {
      days: [
        { date: manilaDay(-1), steps: 900 },
        { date: manilaDay(6), steps: 600 },
        { date: manilaDay(7), steps: 700 },
        { date: today, steps: 100 },
      ],
    }).expect(200);
    assert.deepEqual(res.body.data.skipped, [manilaDay(-1), manilaDay(7)]);
    assert.equal(res.body.data.days[0].steps, 600);
    assert.equal(res.body.data.days[6].steps, 100);
    assert.equal(await savedRows(userId), 2);
  });

  await t.test('a malformed list is refused and saves nothing', async () => {
    const { userId, token } = await freshUser();
    const listMessage = 'days must be a list of 1 to 7 { date, steps } entries.';
    const ok = { date: today, steps: 100 };
    const eight = [0, 1, 2, 3, 4, 5, 6, 7].map((back) => ({ date: manilaDay(back), steps: 10 }));
    const cases = [
      ['no body', undefined, listMessage],
      ['days not a list', { days: ok }, listMessage],
      ['an empty list', { days: [] }, listMessage],
      ['eight entries', { days: eight }, listMessage],
      ['a null entry', { days: [ok, null] }, listMessage],
      ['a string entry', { days: [ok, '2026-11-01'] }, listMessage],
      ['a repeated date', { days: [ok, { date: today, steps: 200 }] }, 'Each day can be sent only once.'],
    ];
    for (const [name, payload, message] of cases) {
      const res = await putBatch(token, payload).expect(400);
      assert.equal(res.body.error.code, 'DAYS_INVALID', name);
      assert.equal(res.body.error.message, message, name);
    }
    assert.equal(await savedRows(userId), 0);
  });

  await t.test('a bad date or step count in one entry saves none of them', async () => {
    const { userId, token } = await freshUser();
    const ok = { date: manilaDay(1), steps: 100 };
    const bad = await putBatch(token, { days: [ok, { date: '2026-02-30', steps: 10 }] }).expect(400);
    assert.equal(bad.body.error.code, 'DATE_INVALID');
    assert.equal(bad.body.error.message, 'date must be a real YYYY-MM-DD day.');
    for (const steps of [-1, 1.5, 100001]) {
      const res = await putBatch(token, { days: [ok, { date: today, steps }] }).expect(400);
      assert.equal(res.body.error.code, 'STEPS_INVALID', String(steps));
      assert.equal(res.body.error.message, 'steps must be a whole number from 0 to 100000.');
    }
    assert.equal(await savedRows(userId), 0);
  });

  await t.test("one user never sees another's days", async () => {
    const a = await freshUser();
    const b = await freshUser();
    await put(a.token, today, { steps: 1234 }).expect(200);
    const res = await get(b.token).expect(200);
    assert.equal(res.body.data.days[6].steps, null);
  });
});
