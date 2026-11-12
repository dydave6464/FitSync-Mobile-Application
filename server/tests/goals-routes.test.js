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
      patch: (p, b) => request(app).patch(`/api/v1/goals${p}`).set(auth).send(b),
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
    await request(app).patch('/api/v1/goals/1').send({ targetKg: 70 }).expect(401);
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
      assert.equal(res.body.error.message, 'targetKg must be a number from 0.5 to 999.99.');
      assert.deepEqual(res.body.error.details, [{ field: 'targetKg' }]);
    }
  });

  await t.test('a target at or below the best is refused', async () => {
    const u = await freshUser();
    await lifted(u.userId, squat, 60);
    for (const targetKg of [60, 55]) {
      const res = await u.post({ exerciseId: squat, targetKg }).expect(400);
      assert.equal(res.body.error.code, 'GOAL_ALREADY_MET');
      assert.equal(res.body.error.message, 'Your best is already 60 kg.');
      assert.deepEqual(res.body.error.details, [{ field: 'targetKg', bestKg: 60 }]);
    }
    await u.post({ exerciseId: squat, targetKg: 62.5 }).expect(201);
  });

  await t.test('a decimal best is sent as a number', async () => {
    const u = await freshUser();
    await lifted(u.userId, squat, 52.5);
    const res = await u.post({ exerciseId: squat, targetKg: 50 }).expect(400);
    assert.equal(res.body.error.code, 'GOAL_ALREADY_MET');
    assert.equal(res.body.error.message, 'Your best is already 52.5 kg.');
    assert.deepEqual(res.body.error.details, [{ field: 'targetKg', bestKg: 52.5 }]);
  });

  await t.test('one unreached goal per exercise; a higher one once it is reached', async () => {
    const u = await freshUser();
    const first = (await u.post({ exerciseId: squat, targetKg: 70 }).expect(201)).body.data.goal;
    const res = await u.post({ exerciseId: squat, targetKg: 80 }).expect(409);
    assert.equal(res.body.error.code, 'GOAL_EXISTS');
    assert.equal(res.body.error.message, 'You already have a goal for this exercise.');
    assert.deepEqual(res.body.error.details, [{ field: 'exerciseId', goalId: first.goalId }]);
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
    assert.equal(options[0].hasOpenGoal, false);
    assert.equal(options[0].goalId, null);

    // Another user's open goal on the same lift does not mark this user's.
    const other = await freshUser();
    await other.post({ exerciseId: press, targetKg: 100 }).expect(201);
    const mine = (await u.get('/options').expect(200)).body.data.options[0];
    assert.equal(mine.hasOpenGoal, false);
    assert.equal(mine.goalId, null);

    const { goalId } = (await u.post({ exerciseId: press, targetKg: 50 }).expect(201)).body.data.goal;
    const marked = (await u.get('/options').expect(200)).body.data.options[0];
    assert.equal(marked.hasOpenGoal, true);
    assert.equal(marked.goalId, goalId);

    await lifted(u.userId, press, 50);
    const reached = (await u.get('/options').expect(200)).body.data.options[0];
    assert.equal(reached.hasOpenGoal, false);
    assert.equal(reached.goalId, null);
  });

  await t.test('two goals for one exercise sent at once: exactly one is created', async () => {
    const u = await freshUser();
    const [r1, r2] = await Promise.all([
      u.post({ exerciseId: press, targetKg: 50 }),
      u.post({ exerciseId: press, targetKg: 55 }),
    ]);
    assert.deepEqual([r1.status, r2.status].sort(), [201, 409]);
    assert.equal((await u.get('').expect(200)).body.data.goals.filter((g) => g.exerciseId === press).length, 1);
    const [won, lost] = r1.status === 201 ? [r1, r2] : [r2, r1];
    assert.deepEqual(lost.body.error.details,
      [{ field: 'exerciseId', goalId: won.body.data.goal.goalId }]);
  });

  await t.test('changing the target returns the updated goal', async () => {
    const u = await freshUser();
    const created = (await u.post({ exerciseId: squat, targetKg: 60 }).expect(201)).body.data.goal;
    const res = await u.patch(`/${created.goalId}`, { targetKg: 70 }).expect(200);
    assert.deepEqual(res.body, { data: { goal: { ...created, targetKg: 70 } } });
    const list = (await u.get('').expect(200)).body.data.goals;
    assert.deepEqual(list.map((g) => [g.goalId, g.targetKg]), [[created.goalId, 70]]);

    // Saving the same target again is fine and changes nothing.
    const same = await u.patch(`/${created.goalId}`, { targetKg: 70 }).expect(200);
    assert.deepEqual(same.body.data.goal, { ...created, targetKg: 70 });
  });

  await t.test('a bad target or goal is refused', async () => {
    const a = await freshUser();
    const b = await freshUser();
    const { goalId } = (await a.post({ exerciseId: squat, targetKg: 60 }).expect(201)).body.data.goal;
    for (const targetKg of [0.4, 1000, '60', null]) {
      const res = await a.patch(`/${goalId}`, { targetKg }).expect(400);
      assert.equal(res.body.error.code, 'TARGET_INVALID', `targetKg ${targetKg}`);
      assert.equal(res.body.error.message, 'targetKg must be a number from 0.5 to 999.99.');
      assert.deepEqual(res.body.error.details, [{ field: 'targetKg' }]);
    }

    const bad = await a.patch('/abc', { targetKg: 70 }).expect(404);
    assert.equal(bad.body.error.code, 'GOAL_NOT_FOUND');
    assert.equal(bad.body.error.message, 'No such goal.');

    const theirs = await b.patch(`/${goalId}`, { targetKg: 70 }).expect(404);
    assert.equal(theirs.body.error.code, 'GOAL_NOT_FOUND');
    assert.equal((await a.get('').expect(200)).body.data.goals[0].targetKg, 60);

    await a.del(`/${goalId}`).expect(200);
    const gone = await a.patch(`/${goalId}`, { targetKg: 70 }).expect(404);
    assert.equal(gone.body.error.code, 'GOAL_NOT_FOUND');
  });

  await t.test('a changed target at or below the best is refused with the numbers', async () => {
    const u = await freshUser();
    await lifted(u.userId, squat, 60);
    const { goalId } = (await u.post({ exerciseId: squat, targetKg: 70 }).expect(201)).body.data.goal;
    for (const targetKg of [60, 55]) {
      const res = await u.patch(`/${goalId}`, { targetKg }).expect(400);
      assert.equal(res.body.error.code, 'GOAL_ALREADY_MET');
      assert.equal(res.body.error.message, 'Your best is already 60 kg.');
      assert.deepEqual(res.body.error.details, [{ field: 'targetKg', bestKg: 60 }]);
    }
    const lowered = await u.patch(`/${goalId}`, { targetKg: 62.5 }).expect(200);
    assert.equal(lowered.body.data.goal.targetKg, 62.5);
  });

  await t.test('a reached goal cannot be changed', async () => {
    const u = await freshUser();
    const { goalId } = (await u.post({ exerciseId: squat, targetKg: 70 }).expect(201)).body.data.goal;
    await lifted(u.userId, squat, 70);
    const res = await u.patch(`/${goalId}`, { targetKg: 80 }).expect(409);
    assert.equal(res.body.error.code, 'GOAL_REACHED');
    assert.equal(res.body.error.message, "You've reached this goal. Add a new one to aim higher.");
    const [{ reachedOn }] = (await u.get('').expect(200)).body.data.goals;
    assert.equal(typeof reachedOn, 'string');
    assert.deepEqual(res.body.error.details, [{ field: 'goalId', goalId, reachedOn }]);

    // Still one open goal at most: a new goal for the lift is allowed.
    await u.post({ exerciseId: squat, targetKg: 80 }).expect(201);
  });
});
