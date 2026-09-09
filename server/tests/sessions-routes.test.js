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

  // freshUser's plan, but with `rotation` days. Raw SQL for the same reason
  // freshUser uses it: the plans router and the ML stub are another file's
  // business, and a session test that depended on them would fail for
  // reasons that have nothing to do with sessions.
  const freshUserWithRotation = async (email, rotation) => {
    const made = await freshUser(email);
    await pool.query('DELETE FROM plan_exercises');
    await pool.query('UPDATE workout_plans SET split_style = ? WHERE user_id = ?',
      ['push_pull_legs', made.userId]);
    const [plan] = await pool.query(
      'SELECT plan_id FROM workout_plans WHERE user_id = ? AND is_active = TRUE',
      [made.userId],
    );
    for (let dayNo = 1; dayNo <= rotation; dayNo += 1) {
      await pool.query(
        `INSERT INTO plan_exercises (plan_id, exercise_id, day_no, order_no, target_sets, target_reps)
         VALUES (?, ?, ?, 1, 3, '8-12')`,
        [plan[0].plan_id, made.exerciseId, dayNo],
      );
    }
    return made;
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

  // started_at is a TIMESTAMP, and MySQL renders TIMESTAMP columns in the
  // session's time_zone -- 'SYSTEM' on a default install -- on the way out.
  // The pool's mysql2 `timezone: 'Z'` then LABELS that local wall-clock string
  // as UTC, so a server running at UTC+8 reports a session as having started
  // eight hours in the future. The phone subtracts that from its own clock,
  // gets a negative, clamps it to zero, and the workout shows "0 min elapsed"
  // forever -- and stores durationMin: 0 on completion. getProfile already
  // solved this for created_at with UNIX_TIMESTAMP(); this pins it for
  // started_at too.
  await t.test('startedAt is the real instant, not the server wall clock', async () => {
    const { token } = await freshUser('clock@example.com');

    const before = Date.now();
    const res = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const startedAt = Date.parse(res.body.data.session.startedAt);

    // The row was inserted between these two readings, so its instant has to
    // fall between them. A timezone-mislabelled value misses by whole hours.
    assert.ok(
      startedAt >= before - 1000 && startedAt <= Date.now() + 1000,
      `startedAt ${res.body.data.session.startedAt} is not within the request `
      + `window (${new Date(before).toISOString()} .. ${new Date().toISOString()})`,
    );
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

  await t.test('a set round-trips as numbers', async () => {
    const { token, exerciseId } = await freshUser('sets@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;

    const res = await auth(request(app).put(`/api/v1/sessions/${id}/sets`), token)
      .send({ exerciseId, setNumber: 1, weightKg: 22.5, reps: 10 }).expect(200);
    assert.deepEqual(res.body.data.set, { exerciseId, setNumber: 1, weightKg: 22.5, reps: 10 });

    const active = await auth(request(app).get('/api/v1/sessions/active'), token).expect(200);
    assert.strictEqual(active.body.data.session.sets[0].weightKg, 22.5);
  });

  await t.test('validation rejects each bad field with its own code', async () => {
    const { token, exerciseId } = await freshUser('bad@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;
    const put = () => auth(request(app).put(`/api/v1/sessions/${id}/sets`), token);

    const cases = [
      [{ exerciseId, setNumber: 0, weightKg: 20, reps: 8 }, 'SET_NUMBER_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: 20, reps: 1000 }, 'REPS_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: 1000, reps: 8 }, 'WEIGHT_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: -1, reps: 8 }, 'WEIGHT_INVALID'],
      [{ setNumber: 1, weightKg: 20, reps: 8 }, 'EXERCISE_NOT_IN_PLAN'],
      // Below: more than one field is bad at once, so the code returned
      // actually pins the CHECK ORDER (setNumber, weightKg, reps,
      // exerciseId) rather than merely confirming each field has its own
      // bound. A reordered implementation would report a different code for
      // at least one of these three.
      [{ exerciseId, setNumber: 0, weightKg: 1000, reps: 1000 }, 'SET_NUMBER_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: 1000, reps: 1000 }, 'WEIGHT_INVALID'],
      [{ setNumber: 1, weightKg: 20, reps: 1000 }, 'REPS_INVALID'],
      // Not a number at all. Number('') and Number([]) are both 0 and
      // Number(true) is 1, so these used to be COERCED and stored -- an empty
      // weight field arriving as '' became a recorded 0.00 kg lift rather
      // than "not recorded". Only null and undefined mean not recorded.
      [{ exerciseId, setNumber: 1, weightKg: '', reps: 8 }, 'WEIGHT_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: '   ', reps: 8 }, 'WEIGHT_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: [], reps: 8 }, 'WEIGHT_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: true, reps: 8 }, 'WEIGHT_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: '22.5', reps: 8 }, 'WEIGHT_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: 20, reps: '' }, 'REPS_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: 20, reps: '8' }, 'REPS_INVALID'],
      [{ exerciseId, setNumber: 1, weightKg: 20, reps: 8.5 }, 'REPS_INVALID'],
    ];
    for (const [body, code] of cases) {
      const res = await put().send(body).expect(400);
      assert.equal(res.body.error.code, code, `expected ${code} for ${JSON.stringify(body)}`);
    }
  });

  await t.test('null weight and null reps are accepted', async () => {
    const { token, exerciseId } = await freshUser('bw@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;

    const res = await auth(request(app).put(`/api/v1/sessions/${id}/sets`), token)
      .send({ exerciseId, setNumber: 1, weightKg: null, reps: null }).expect(200);
    assert.equal(res.body.data.set.weightKg, null);
  });

  await t.test('un-ticking returns 200 twice, never 204', async () => {
    const { token, exerciseId } = await freshUser('untick@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;
    await auth(request(app).put(`/api/v1/sessions/${id}/sets`), token)
      .send({ exerciseId, setNumber: 1, weightKg: 20, reps: 10 }).expect(200);

    const path = `/api/v1/sessions/${id}/sets/${exerciseId}/1`;
    const first = await auth(request(app).delete(path), token).expect(200);
    assert.equal(first.body.data.deleted, true);
    await auth(request(app).delete(path), token).expect(200);

    const active = await auth(request(app).get('/api/v1/sessions/active'), token).expect(200);
    assert.deepEqual(active.body.data.session.sets, []);
  });

  await t.test("another user's session cannot get a set logged either: 404", async () => {
    const mine = await freshUser('setmine@example.com');
    const theirs = await freshUser('settheirs@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), mine.token).expect(201);
    const id = started.body.data.session.sessionId;

    const stolen = await auth(request(app).put(`/api/v1/sessions/${id}/sets`), theirs.token)
      .send({ exerciseId: mine.exerciseId, setNumber: 1, weightKg: 20, reps: 8 }).expect(404);
    assert.equal(stolen.body.error.code, 'SESSION_NOT_FOUND');
  });

  await t.test("another user's set cannot be deleted either: 404, and it survives", async () => {
    const mine = await freshUser('delmine@example.com');
    const theirs = await freshUser('deltheirs@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), mine.token).expect(201);
    const id = started.body.data.session.sessionId;
    await auth(request(app).put(`/api/v1/sessions/${id}/sets`), mine.token)
      .send({ exerciseId: mine.exerciseId, setNumber: 1, weightKg: 20, reps: 8 }).expect(200);

    const stolen = await auth(
      request(app).delete(`/api/v1/sessions/${id}/sets/${mine.exerciseId}/1`), theirs.token,
    ).expect(404);
    assert.equal(stolen.body.error.code, 'SESSION_NOT_FOUND');

    // A return-value check alone would pass even if the DELETE actually ran
    // against the row -- confirm the owner's set is still there.
    const active = await auth(request(app).get('/api/v1/sessions/active'), mine.token).expect(200);
    assert.equal(active.body.data.session.sets.length, 1);
  });

  await t.test('logging a set on a closed session is 409 SESSION_NOT_IN_PROGRESS', async () => {
    const { token, exerciseId } = await freshUser('closedset@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;
    await auth(request(app).post(`/api/v1/sessions/${id}/complete`), token)
      .send({ durationMin: 20 }).expect(200);

    const res = await auth(request(app).put(`/api/v1/sessions/${id}/sets`), token)
      .send({ exerciseId, setNumber: 1, weightKg: 20, reps: 8 }).expect(409);
    assert.equal(res.body.error.code, 'SESSION_NOT_IN_PROGRESS');
  });

  await t.test('last performance comes back for the exercises asked for', async () => {
    const { token, exerciseId } = await freshUser('prev@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    const id = started.body.data.session.sessionId;
    await auth(request(app).put(`/api/v1/sessions/${id}/sets`), token)
      .send({ exerciseId, setNumber: 1, weightKg: 30, reps: 6 }).expect(200);
    await auth(request(app).post(`/api/v1/sessions/${id}/complete`), token)
      .send({ durationMin: 40 }).expect(200);

    const res = await auth(
      request(app).get(`/api/v1/sessions/last-performance?exerciseIds=${exerciseId}`), token,
    ).expect(200);
    assert.equal(res.body.data.performances.length, 1);
    assert.strictEqual(res.body.data.performances[0].weightKg, 30);
  });

  await t.test('last performance with no ids returns an empty list, not an error', async () => {
    const { token } = await freshUser('noids@example.com');
    const res = await auth(request(app).get('/api/v1/sessions/last-performance'), token).expect(200);
    assert.deepEqual(res.body.data.performances, []);
  });

  await t.test('last performance with an empty exerciseIds string also returns an empty list', async () => {
    const { token } = await freshUser('emptyids@example.com');
    const res = await auth(
      request(app).get('/api/v1/sessions/last-performance?exerciseIds='), token,
    ).expect(200);
    assert.deepEqual(res.body.data.performances, []);
  });

  await t.test('the week lists the completed day', async () => {
    const { token } = await freshUser('week@example.com');
    const started = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    await auth(request(app).post(`/api/v1/sessions/${started.body.data.session.sessionId}/complete`), token)
      .send({ durationMin: 35 }).expect(200);

    const res = await auth(request(app).get('/api/v1/sessions/week'), token).expect(200);
    assert.equal(res.body.data.dates.length, 1);
  });

  // today's day = (sessions completed this week mod rotation) + 1. Counting
  // completions rather than mapping weekdays is what stops a missed Monday
  // stranding someone on Push until next week.
  await t.test('the first session of the week is day one', async () => {
    const { token } = await freshUser('day1@example.com');
    const res = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    assert.equal(res.body.data.session.planDayNo, 1);
  });

  await t.test('the next session is the next day in the rotation', async () => {
    const { token } = await freshUserWithRotation('day2@example.com', 3);

    const first = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    assert.equal(first.body.data.session.planDayNo, 1);
    await auth(
      request(app).post(`/api/v1/sessions/${first.body.data.session.sessionId}/complete`),
      token,
    ).send({ durationMin: 30 }).expect(200);

    const second = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    assert.equal(second.body.data.session.planDayNo, 2);
  });

  await t.test('the rotation wraps inside one week', async () => {
    const { token } = await freshUserWithRotation('daywrap@example.com', 3);

    // Three completed sessions, then the fourth is day 1 again -- which is
    // what a four-day push/pull/legs week is.
    for (let i = 0; i < 3; i += 1) {
      const s = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
      await auth(
        request(app).post(`/api/v1/sessions/${s.body.data.session.sessionId}/complete`),
        token,
      ).send({ durationMin: 30 }).expect(200);
    }
    const fourth = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    assert.equal(fourth.body.data.session.planDayNo, 1);
  });

  await t.test('an abandoned session does not advance the rotation', async () => {
    const { token } = await freshUserWithRotation('dayabandon@example.com', 3);

    const first = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    await auth(
      request(app).post(`/api/v1/sessions/${first.body.data.session.sessionId}/abandon`),
      token,
    ).expect(200);

    const retry = await auth(request(app).post('/api/v1/sessions'), token).expect(201);
    assert.equal(retry.body.data.session.planDayNo, 1, 'giving up does not cost a day');
  });

  await t.test('every route requires a token', async () => {
    await request(app).get('/api/v1/sessions/active').expect(401);
    await request(app).post('/api/v1/sessions').expect(401);
    await request(app).post('/api/v1/sessions/1/complete').expect(401);
    await request(app).post('/api/v1/sessions/1/abandon').expect(401);
    await request(app).put('/api/v1/sessions/1/sets').expect(401);
    await request(app).delete('/api/v1/sessions/1/sets/1/1').expect(401);
    await request(app).get('/api/v1/sessions/last-performance').expect(401);
    await request(app).get('/api/v1/sessions/week').expect(401);
  });
});
