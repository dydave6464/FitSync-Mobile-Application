'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { createStorage } = require('../src/services/storage');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { markEmailVerified } = require('../src/db/users');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('session endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  const [live] = await pool.query("SELECT name FROM exercises WHERE status='live' LIMIT 1");
  const known = live[0].name;

  const ml = {
    generatePlan: async () => ({
      name: 'Starter Plan', splitStyle: 'full_body', daysPerWeek: 3,
      sessionLengthMin: 45, weekNo: 1,
      exercises: [{ name: known, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
    }),
    estimateInjuryRisk: async () => ({ riskLevel: 'low', trainingLoadScore: 0 }),
  };

  const app = buildTestApp({
    pool, ml, storage: createStorage({ mode: 'local', localDir: 'storage' }),
  });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  // Registers a fresh verified user, gives them an active plan, and returns
  // { token, exerciseId }. Each subtest starts from a clean slate.
  const freshUser = async (email) => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'W' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const token = login.body.data.token;
    const userId = res.body.data.user.userId;

    const [ex] = await pool.query("SELECT exercise_id FROM exercises WHERE status='live' LIMIT 1");
    const [plan] = await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min)
       VALUES (?, 'Plan', 'full_body', 3, 45)`,
      [userId],
    );
    await pool.query(
      `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps)
       VALUES (?, ?, 1, 3, '8-12')`,
      [plan.insertId, ex[0].exercise_id],
    );
    return { token, userId, exerciseId: ex[0].exercise_id };
  };

  const auth = (req, token) => req.set('Authorization', `Bearer ${token}`);

  await t.test('no session in progress reads as null, not 404', async () => {
    const { token } = await freshUser('none@example.com');
    const res = await auth(request(app).get('/api/v1/sessions/active'), token).expect(200);
    assert.equal(res.body.data.session, null);
  });

  await t.test('starting returns 201, starting again returns 200 and the same id', async () => {
    const { token } = await freshUser('start@example.com');

    const first = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    assert.equal(first.body.data.session.status, 'in_progress');

    // Confirms GET /active reflects the real row, not a stub -- a handler
    // hardcoded to always return null would still pass every other
    // assertion in this file, since they only ever check the empty case.
    const active = await auth(request(app).get('/api/v1/sessions/active'), token).expect(200);
    assert.equal(active.body.data.session.sessionId, first.body.data.session.sessionId);

    const second = await auth(request(app).post('/api/v1/sessions'), token).expect(200);
    assert.equal(second.body.data.session.sessionId, first.body.data.session.sessionId);
  });

  await t.test('starting without a plan is 409 NO_ACTIVE_PLAN', async () => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'noplan@example.com', password: 's3cret-pass', fullName: 'W' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'noplan@example.com', password: 's3cret-pass' }).expect(200);

    const started = await auth(request(app).post('/api/v1/sessions'), login.body.data.token).expect(409);
    assert.equal(started.body.error.code, 'NO_ACTIVE_PLAN');
  });

  await t.test('completing returns the closed session and clears active', async () => {
    const { token } = await freshUser('done@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;

    const done = await auth(request(app).post(`/api/v1/sessions/${id}/complete`), token)
      .send({ durationMin: 42 }).expect(200);
    assert.equal(done.body.data.session.status, 'completed');
    assert.equal(done.body.data.session.durationMin, 42);

    const active = await auth(request(app).get('/api/v1/sessions/active'), token).expect(200);
    assert.equal(active.body.data.session, null);
  });

  await t.test('completing twice is 409 SESSION_NOT_IN_PROGRESS', async () => {
    const { token } = await freshUser('twice@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;

    await auth(request(app).post(`/api/v1/sessions/${id}/complete`), token)
      .send({ durationMin: 30 }).expect(200);
    const again = await auth(request(app).post(`/api/v1/sessions/${id}/complete`), token)
      .send({ durationMin: 30 }).expect(409);
    assert.equal(again.body.error.code, 'SESSION_NOT_IN_PROGRESS');
  });

  await t.test('a bad duration is rejected', async () => {
    const { token } = await freshUser('badtime@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;

    const res = await auth(request(app).post(`/api/v1/sessions/${id}/complete`), token)
      .send({ durationMin: -5 }).expect(400);
    assert.equal(res.body.error.code, 'DURATION_INVALID');
  });

  await t.test('a duration above the upper bound is rejected', async () => {
    const { token } = await freshUser('toolong@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;

    const res = await auth(request(app).post(`/api/v1/sessions/${id}/complete`), token)
      .send({ durationMin: 1441 }).expect(400);
    assert.equal(res.body.error.code, 'DURATION_INVALID');
  });

  await t.test('a missing duration is rejected', async () => {
    const { token } = await freshUser('noduration@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;

    const res = await auth(request(app).post(`/api/v1/sessions/${id}/complete`), token)
      .send({}).expect(400);
    assert.equal(res.body.error.code, 'DURATION_INVALID');
  });

  await t.test("another user's session is 404, and so is a non-numeric id", async () => {
    const mine = await freshUser('mine@example.com');
    const theirs = await freshUser('theirs@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), mine.token).expect(201);
    const id = started.body.data.session.sessionId;

    const stolen = await auth(request(app).post(`/api/v1/sessions/${id}/complete`), theirs.token)
      .send({ durationMin: 10 }).expect(404);
    assert.equal(stolen.body.error.code, 'SESSION_NOT_FOUND');

    await auth(request(app).post('/api/v1/sessions/abc/complete'), mine.token)
      .send({ durationMin: 10 }).expect(404);
  });

  await t.test("another user's session cannot be abandoned either: 404", async () => {
    const mine = await freshUser('mineabandon@example.com');
    const theirs = await freshUser('theirsabandon@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), mine.token).expect(201);
    const id = started.body.data.session.sessionId;

    const stolen = await auth(request(app).post(`/api/v1/sessions/${id}/abandon`), theirs.token).expect(404);
    assert.equal(stolen.body.error.code, 'SESSION_NOT_FOUND');

    await auth(request(app).post('/api/v1/sessions/abc/abandon'), mine.token).expect(404);
  });

  await t.test('abandoning closes the session', async () => {
    const { token } = await freshUser('quit@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;

    const res = await auth(request(app).post(`/api/v1/sessions/${id}/abandon`), token).expect(200);
    assert.equal(res.body.data.abandoned, true);

    const active = await auth(request(app).get('/api/v1/sessions/active'), token).expect(200);
    assert.equal(active.body.data.session, null);
  });

  await t.test('every route requires a token', async () => {
    await request(app).get('/api/v1/sessions/active').expect(401);
    await request(app).post('/api/v1/sessions').expect(401);
  });
});
