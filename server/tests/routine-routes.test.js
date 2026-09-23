'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('routine endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  // The server's own weekday, so "scheduled today" tests track CURDATE().
  const [[{ today }]] = await pool.query('SELECT WEEKDAY(CURDATE()) + 1 AS today');
  const notToday = (Number(today) % 7) + 1;
  const ALL = [1, 2, 3, 4, 5, 6, 7];

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `rr${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'R' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return login.body.data.token;
  };

  const api = (token) => ({
    get: (p) => request(app).get(`/api/v1/routine${p}`).set('Authorization', `Bearer ${token}`),
    post: (p, b) => request(app).post(`/api/v1/routine${p}`).set('Authorization', `Bearer ${token}`).send(b),
    patch: (p, b) => request(app).patch(`/api/v1/routine${p}`).set('Authorization', `Bearer ${token}`).send(b),
    put: (p) => request(app).put(`/api/v1/routine${p}`).set('Authorization', `Bearer ${token}`),
    del: (p) => request(app).delete(`/api/v1/routine${p}`).set('Authorization', `Bearer ${token}`),
  });

  await t.test('today requires sign-in', async () => {
    await request(app).get('/api/v1/routine/today').expect(401);
  });

  await t.test('a new account has an empty day and no workout item', async () => {
    const res = await api(await freshUser()).get('/today').expect(200);
    assert.match(res.body.data.date, /^\d{4}-\d{2}-\d{2}$/);
    assert.deepEqual(res.body.data.habits, []);
    assert.equal(res.body.data.workout, null);
  });

  await t.test('a created habit is listed today and can be ticked and unticked', async () => {
    const a = api(await freshUser());
    const created = await a.post('/habits', {
      title: '  Mobility  ', time: '06:30', durationMin: 8, weekdays: ALL,
    }).expect(201);
    const habit = created.body.data.habit;
    assert.equal(habit.title, 'Mobility', 'trimmed');
    assert.equal(habit.time, '06:30');

    await a.put(`/habits/${habit.habitId}/check`).expect(200, { data: { done: true } });
    await a.put(`/habits/${habit.habitId}/check`).expect(200, { data: { done: true } });
    let day = await a.get('/today').expect(200);
    assert.equal(day.body.data.habits[0].done, true);

    await a.del(`/habits/${habit.habitId}/check`).expect(200, { data: { done: false } });
    day = await a.get('/today').expect(200);
    assert.equal(day.body.data.habits[0].done, false);
  });

  await t.test('invalid bodies are refused with a named code', async () => {
    const a = api(await freshUser());
    const cases = [
      [{ weekdays: ALL }, 'TITLE_REQUIRED'],
      [{ title: '   ', weekdays: ALL }, 'TITLE_REQUIRED'],
      [{ title: 'x'.repeat(61), weekdays: ALL }, 'TITLE_TOO_LONG'],
      [{ title: 'A', time: '24:00', weekdays: ALL }, 'TIME_INVALID'],
      [{ title: 'A', time: '6:30', weekdays: ALL }, 'TIME_INVALID'],
      [{ title: 'A', durationMin: 0, weekdays: ALL }, 'DURATION_INVALID'],
      [{ title: 'A', durationMin: 601, weekdays: ALL }, 'DURATION_INVALID'],
      [{ title: 'A', durationMin: 1.5, weekdays: ALL }, 'DURATION_INVALID'],
      [{ title: 'A', weekdays: [] }, 'WEEKDAYS_INVALID'],
      [{ title: 'A', weekdays: [0] }, 'WEEKDAYS_INVALID'],
      [{ title: 'A', weekdays: [1, 1] }, 'WEEKDAYS_INVALID'],
      [{ title: 'A' }, 'WEEKDAYS_INVALID'],
    ];
    for (const [body, code] of cases) {
      const res = await a.post('/habits', body).expect(400);
      assert.equal(res.body.error.code, code, JSON.stringify(body));
    }
  });

  await t.test('patch changes only what is sent, and null clears', async () => {
    const a = api(await freshUser());
    const { habitId } = (await a.post('/habits', {
      title: 'Run', time: '06:00', durationMin: 30, weekdays: ALL,
    })).body.data.habit;

    let res = await a.patch(`/habits/${habitId}`, { title: 'Easy run' }).expect(200);
    assert.equal(res.body.data.habit.time, '06:00');
    res = await a.patch(`/habits/${habitId}`, { time: null, durationMin: null }).expect(200);
    assert.equal(res.body.data.habit.time, null);
    assert.equal(res.body.data.habit.durationMin, null);

    const bad = await a.patch(`/habits/${habitId}`, { weekdays: [] }).expect(400);
    assert.equal(bad.body.error.code, 'WEEKDAYS_INVALID');
  });

  await t.test('delete hides the habit; it is then not found', async () => {
    const a = api(await freshUser());
    const { habitId } = (await a.post('/habits', { title: 'Gone', weekdays: ALL })).body.data.habit;
    await a.del(`/habits/${habitId}`).expect(200, { data: { deleted: true } });
    assert.deepEqual((await a.get('/today')).body.data.habits, []);
    const res = await a.del(`/habits/${habitId}`).expect(404);
    assert.equal(res.body.error.code, 'HABIT_NOT_FOUND');
    await a.put(`/habits/${habitId}/check`).expect(404);
  });

  await t.test("another user's habit is not found on every route", async () => {
    const owner = api(await freshUser());
    const other = api(await freshUser());
    const { habitId } = (await owner.post('/habits', { title: 'Mine', weekdays: ALL })).body.data.habit;
    await other.patch(`/habits/${habitId}`, { title: 'x' }).expect(404);
    await other.del(`/habits/${habitId}`).expect(404);
    await other.put(`/habits/${habitId}/check`).expect(404);
    await other.del(`/habits/${habitId}/check`).expect(404);
  });

  await t.test('a non-numeric id is not found', async () => {
    await api(await freshUser()).put('/habits/abc/check').expect(404);
  });

  await t.test('a habit not scheduled today cannot be ticked', async () => {
    const a = api(await freshUser());
    const { habitId } = (await a.post('/habits', { title: 'Later', weekdays: [notToday] })).body.data.habit;
    const res = await a.put(`/habits/${habitId}/check`).expect(400);
    assert.equal(res.body.error.code, 'HABIT_NOT_TODAY');
  });
});
