'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { createStorage } = require('../src/services/storage');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('session detail', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  const app = buildTestApp({
    pool, storage: createStorage({ mode: 'local', localDir: 'storage' }),
  });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `detail${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'W' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { token: login.body.data.token, userId: res.body.data.user.userId };
  };

  // Equipment under its curated name, so the detail is seen to speak the
  // same vocabulary as the logger rather than the raw tag.
  const [bar] = await pool.query(
    "INSERT INTO equipment (name, display_name) VALUES ('barbell', 'Barbell')",
  );

  const exercise = async (name, muscle, { equipmentId = bar.insertId } = {}) => {
    const [x] = await pool.query(
      `INSERT INTO exercises (name, muscle_group, status, equipment_id, thumbnail_url)
       VALUES (?, ?, 'live', ?, ?)`,
      [name, muscle, equipmentId, `exercises/${name.replace(/\W+/g, '-')}/thumb.jpg`],
    );
    return x.insertId;
  };

  const bench = await exercise('Barbell Bench Press', 'chest');
  const fly = await exercise('Barbell Fly', 'chest');
  const row = await exercise('Barbell Row', 'back');
  const pushUp = await exercise('Push-up', 'chest', { equipmentId: null });

  // The real start / log / complete flow, so the totals read back are the
  // ones completeSession computed rather than ones this file wrote.
  const start = async (token, exerciseIds) => {
    const res = await request(app).post('/api/v1/sessions')
      .set('Authorization', `Bearer ${token}`)
      .send(exerciseIds ? { exerciseIds } : {})
      .expect(201);
    return res.body.data.session.sessionId;
  };
  const log = (token, sessionId, exerciseId, setNumber, weightKg, reps) => request(app)
    .put(`/api/v1/sessions/${sessionId}/sets`)
    .set('Authorization', `Bearer ${token}`)
    .send({ exerciseId, setNumber, weightKg, reps })
    .expect(200);
  const finish = (token, sessionId, durationMin = 52) => request(app)
    .post(`/api/v1/sessions/${sessionId}/complete`)
    .set('Authorization', `Bearer ${token}`)
    .send({ durationMin })
    .expect(200);
  const detail = (token, id) => request(app)
    .get(`/api/v1/sessions/${id}`)
    .set('Authorization', `Bearer ${token}`);

  await t.test('a hand-picked session reads back what was trained', async () => {
    const u = await freshUser();
    const id = await start(u.token, [bench, fly, row]);
    await log(u.token, id, bench, 1, 62.5, 8);
    await log(u.token, id, bench, 2, 60, 8);
    await log(u.token, id, row, 1, 40, 10);
    await finish(u.token, id);

    const res = await detail(u.token, id).expect(200);
    const s = res.body.data.session;

    assert.equal(s.sessionId, id);
    assert.match(s.sessionDate, /^\d{4}-\d{2}-\d{2}$/);
    assert.match(s.startedAt, /^\d{4}-\d{2}-\d{2}T/);
    assert.equal(s.durationMin, 52);
    assert.equal(s.totalVolumeKg, 62.5 * 8 + 60 * 8 + 40 * 10);
    assert.equal(s.setCount, 3);
    assert.equal(s.planName, null);
    assert.equal(s.planDayNo, null);
    // The whole list, in list order, repeats kept -- what names it in History,
    // the fly included although nothing was logged for it.
    assert.deepEqual(s.muscleGroups, ['chest', 'chest', 'back']);

    // Only what was logged; weights as numbers, never '62.50'.
    assert.deepEqual(s.exercises, [
      {
        exerciseId: bench,
        name: 'Barbell Bench Press',
        muscleGroup: 'chest',
        equipment: 'Barbell',
        thumbnailUrl: '/storage/exercises/Barbell-Bench-Press/thumb.jpg',
        volumeKg: 980,
        sets: [
          { setNumber: 1, weightKg: 62.5, reps: 8 },
          { setNumber: 2, weightKg: 60, reps: 8 },
        ],
      },
      {
        exerciseId: row,
        name: 'Barbell Row',
        muscleGroup: 'back',
        equipment: 'Barbell',
        thumbnailUrl: '/storage/exercises/Barbell-Row/thumb.jpg',
        volumeKg: 400,
        sets: [{ setNumber: 1, weightKg: 40, reps: 10 }],
      },
    ]);
  });

  await t.test('a plan session is named by its plan and carries no muscles', async () => {
    const u = await freshUser();
    const [plan] = await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, is_active)
       VALUES (?, 'Push Pull Legs', 'push_pull_legs', 3, 45, TRUE)`,
      [u.userId],
    );
    await pool.query(
      `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps)
       VALUES (?, ?, 1, 3, '8-12')`,
      [plan.insertId, bench],
    );
    const id = await start(u.token);
    await log(u.token, id, bench, 1, 50, 10);
    await finish(u.token, id);

    const s = (await detail(u.token, id).expect(200)).body.data.session;

    assert.equal(s.planName, 'Push Pull Legs');
    assert.equal(s.planDayNo, 1);
    assert.deepEqual(s.muscleGroups, []);
    assert.deepEqual(s.exercises.map((e) => e.exerciseId), [bench]);
    assert.deepEqual(s.exercises[0].sets, [{ setNumber: 1, weightKg: 50, reps: 10 }]);
  });

  await t.test('exercises come in the order first logged, sets in set order', async () => {
    const u = await freshUser();
    const id = await start(u.token, [bench, row]);
    // row's id is the higher one, and it is logged first -- set 2 before 1.
    assert.ok(row > bench);
    await log(u.token, id, row, 2, 45, 8);
    await log(u.token, id, row, 1, 40, 10);
    await log(u.token, id, bench, 1, 60, 8);
    await finish(u.token, id);

    const s = (await detail(u.token, id).expect(200)).body.data.session;

    assert.deepEqual(s.exercises.map((e) => e.exerciseId), [row, bench]);
    assert.deepEqual(s.exercises[0].sets.map((x) => x.setNumber), [1, 2]);
  });

  await t.test('a bodyweight set has no weight and its exercise no volume', async () => {
    const u = await freshUser();
    const id = await start(u.token, [pushUp]);
    await log(u.token, id, pushUp, 1, null, 12);
    await log(u.token, id, pushUp, 2, null, 10);
    await finish(u.token, id);

    const s = (await detail(u.token, id).expect(200)).body.data.session;

    assert.equal(s.totalVolumeKg, 0);
    assert.equal(s.exercises[0].volumeKg, null);
    assert.equal(s.exercises[0].equipment, null);
    assert.deepEqual(s.exercises[0].sets, [
      { setNumber: 1, weightKg: null, reps: 12 },
      { setNumber: 2, weightKg: null, reps: 10 },
    ]);
  });

  await t.test('sets that were not completed are left out', async () => {
    const u = await freshUser();
    const id = await start(u.token, [bench, row]);
    await log(u.token, id, bench, 1, 60, 8);
    await log(u.token, id, bench, 2, 60, 8);
    await log(u.token, id, row, 1, 40, 10);
    await pool.query(
      `UPDATE set_logs SET is_completed = FALSE
        WHERE session_id = ? AND ((exercise_id = ? AND set_number = 2) OR exercise_id = ?)`,
      [id, bench, row],
    );
    await finish(u.token, id);

    const s = (await detail(u.token, id).expect(200)).body.data.session;

    assert.equal(s.setCount, 1);
    assert.deepEqual(s.exercises.map((e) => e.exerciseId), [bench]);
    assert.deepEqual(s.exercises[0].sets, [{ setNumber: 1, weightKg: 60, reps: 8 }]);
    assert.equal(s.exercises[0].volumeKg, 480);
  });

  await t.test('an exercise demoted since is still listed', async () => {
    const u = await freshUser();
    const demoted = await exercise('Cable Crossover', 'chest');
    const id = await start(u.token, [demoted]);
    await log(u.token, id, demoted, 1, 20, 12);
    await finish(u.token, id);
    await pool.query("UPDATE exercises SET status = 'pending' WHERE exercise_id = ?", [demoted]);

    const s = (await detail(u.token, id).expect(200)).body.data.session;

    assert.deepEqual(s.exercises.map((e) => e.exerciseId), [demoted]);
  });

  await t.test('a finished session with no sets has no exercises', async () => {
    const u = await freshUser();
    const id = await start(u.token, [bench]);
    await finish(u.token, id);

    const s = (await detail(u.token, id).expect(200)).body.data.session;

    assert.deepEqual(s.exercises, []);
    assert.equal(s.setCount, 0);
    assert.equal(s.totalVolumeKg, 0);
  });

  await t.test('thumbnails are URLs, not storage keys', async () => {
    const u = await freshUser();
    const id = await start(u.token, [bench]);
    await log(u.token, id, bench, 1, 60, 8);
    await finish(u.token, id);

    const s = (await detail(u.token, id).expect(200)).body.data.session;

    assert.match(s.exercises[0].thumbnailUrl, /^\/storage\//);
  });

  await t.test('one 404 for every session that is not yours to read', async () => {
    const u = await freshUser();
    const other = await freshUser();

    const abandoned = await start(u.token, [bench]);
    await request(app).post(`/api/v1/sessions/${abandoned}/abandon`)
      .set('Authorization', `Bearer ${u.token}`).expect(200);

    const theirs = await start(other.token, [bench]);
    await finish(other.token, theirs);

    const open = await start(u.token, [bench]);

    for (const id of [open, abandoned, theirs, 999999, 'abc']) {
      const res = await detail(u.token, id);
      assert.equal(res.status, 404, `GET /sessions/${id}`);
      assert.deepEqual(
        { code: res.body.error.code, message: res.body.error.message },
        { code: 'SESSION_NOT_FOUND', message: 'No such session.' },
        `GET /sessions/${id}`,
      );
    }
  });

  await t.test('the fixed paths are never read as a session id', async () => {
    const u = await freshUser();
    const id = await start(u.token, [bench]);
    await log(u.token, id, bench, 1, 60, 8);
    await finish(u.token, id);
    const get = async (path) => (await request(app).get(`/api/v1/sessions${path}`)
      .set('Authorization', `Bearer ${u.token}`).expect(200)).body.data;

    assert.ok(Object.hasOwn(await get('/active'), 'session'));
    assert.equal((await get('/last')).session.sessionId, id);
    assert.ok(Object.hasOwn(await get('/pending-outcome'), 'session'));
    assert.ok(Array.isArray((await get('/week')).dates));
    assert.equal((await get('/summary')).summary.sessionCount, 1);
    assert.equal((await get('/analytics')).period, 'week');
    assert.ok(Array.isArray((await get('/strength')).options));
    assert.ok(Array.isArray((await get(`/last-performance?exerciseIds=${bench}`)).performances));
  });

  await t.test('reading a session needs a signed-in caller', async () => {
    await request(app).get('/api/v1/sessions/1').expect(401);
    await request(app).get('/api/v1/sessions/1')
      .set('Authorization', 'Bearer not-a-token').expect(401);
  });
});
