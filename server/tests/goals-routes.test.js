'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('goal endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [exRows] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE status='live' ORDER BY exercise_id LIMIT 3",
  );
  const [squat, press, hidden] = exRows.map((r) => r.exercise_id);
  // One exercise taken out of the catalogue, for the "not live" refusal.
  await pool.query("UPDATE exercises SET status = 'pending' WHERE exercise_id = ?", [hidden]);

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `gr${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'G' }).expect(201);
    const userId = res.body.data.user.userId;
    await markEmailVerified(pool, userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId,
      get: (p) => request(app).get(`/api/v1/goals${p}`).set(auth),
      post: (b) => request(app).post('/api/v1/goals').set(auth).send(b),
      del: (p) => request(app).delete(`/api/v1/goals${p}`).set(auth),
    };
  };

  /// A completed workout with one set of [exerciseId] at [weightKg].
  const lifted = async (userId, exerciseId, weightKg) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, 'completed', CURDATE())`, [userId],
    );
    await pool.query(
      `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
       VALUES (?, ?, 1, ?, 5, TRUE)`, [s.insertId, exerciseId, weightKg],
    );
  };

  await t.test('every route requires sign-in', async () => {
    await request(app).get('/api/v1/goals').expect(401);
    await request(app).get('/api/v1/goals/options').expect(401);
    await request(app).post('/api/v1/goals').send({ exerciseId: squat, targetKg: 60 }).expect(401);
    await request(app).delete('/api/v1/goals/1').expect(401);
  });

  await t.test('a created goal is returned and listed', async () => {
    const u = await freshUser();
    const created = (await u.post({ exerciseId: squat, targetKg: 60 }).expect(201)).body.data.goal;
    assert.equal(created.exerciseId, squat);
    assert.equal(created.targetKg, 60);
    assert.equal(created.bestKg, null);
    assert.equal(created.reachedOn, null);
    assert.equal(typeof created.exerciseName, 'string');

    const list = (await u.get('').expect(200)).body.data.goals;
    assert.deepEqual(list.map((g) => g.goalId), [created.goalId]);
  });

  await t.test('a bad exercise or target is refused with a named code', async () => {
    const u = await freshUser();
    for (const exerciseId of ['x', 99999999, hidden]) {
      const res = await u.post({ exerciseId, targetKg: 60 }).expect(400);
      assert.equal(res.body.error.code, 'EXERCISE_INVALID', `exerciseId ${exerciseId}`);
    }
    for (const targetKg of [0.4, 1000, '60', null]) {
      const res = await u.post({ exerciseId: squat, targetKg }).expect(400);
      assert.equal(res.body.error.code, 'TARGET_INVALID', `targetKg ${targetKg}`);
    }
  });

  await t.test('a target at or below the best is refused', async () => {
    const u = await freshUser();
    await lifted(u.userId, squat, 60);
    for (const targetKg of [60, 55]) {
      const res = await u.post({ exerciseId: squat, targetKg }).expect(400);
      assert.equal(res.body.error.code, 'GOAL_ALREADY_MET');
      assert.equal(res.body.error.message, 'Your best is already 60 kg.');
    }
    await u.post({ exerciseId: squat, targetKg: 62.5 }).expect(201);
  });

  await t.test('one unreached goal per exercise; a higher one once it is reached', async () => {
    const u = await freshUser();
    await u.post({ exerciseId: squat, targetKg: 70 }).expect(201);
    const res = await u.post({ exerciseId: squat, targetKg: 80 }).expect(409);
    assert.equal(res.body.error.code, 'GOAL_EXISTS');
    await u.post({ exerciseId: press, targetKg: 40 }).expect(201);

    await lifted(u.userId, squat, 70);
    await u.post({ exerciseId: squat, targetKg: 80 }).expect(201);
  });

  await t.test("delete removes a goal; another user's is not found", async () => {
    const a = await freshUser();
    const b = await freshUser();
    const { goalId } = (await a.post({ exerciseId: squat, targetKg: 60 }).expect(201)).body.data.goal;

    const res = await b.del(`/${goalId}`).expect(404);
    assert.equal(res.body.error.code, 'GOAL_NOT_FOUND');
    await b.del('/abc').expect(404);

    await a.del(`/${goalId}`).expect(200, { data: { deleted: true } });
    await a.del(`/${goalId}`).expect(404);
    assert.deepEqual((await a.get('').expect(200)).body.data.goals, []);
  });

  await t.test('options list what the user has lifted', async () => {
    const u = await freshUser();
    await lifted(u.userId, press, 42.5);
    const { options } = (await u.get('/options').expect(200)).body.data;
    assert.equal(options.length, 1);
    assert.equal(options[0].exerciseId, press);
    assert.equal(options[0].bestKg, 42.5);
    assert.equal(options[0].sets, 1);
    assert.equal(typeof options[0].name, 'string');
  });

  await t.test('two goals for one exercise sent at once: exactly one is created', async () => {
    const u = await freshUser();
    const [r1, r2] = await Promise.all([
      u.post({ exerciseId: press, targetKg: 50 }),
      u.post({ exerciseId: press, targetKg: 55 }),
    ]);
    assert.deepEqual([r1.status, r2.status].sort(), [201, 409]);
    assert.equal((await u.get('').expect(200)).body.data.goals.filter((g) => g.exerciseId === press).length, 1);
  });
});
