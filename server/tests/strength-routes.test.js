'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { markEmailVerified } = require('../src/db/users');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('strength routes', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [[ex]] = await pool.query("SELECT exercise_id FROM exercises WHERE status='live' LIMIT 1");

  const res = await request(app).post('/api/v1/auth/register')
    .send({ email: 'st@example.com', password: 's3cret-pass', fullName: 'S' })
    .expect(201);
  const userId = res.body.data.user.userId;
  await markEmailVerified(pool, userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'st@example.com', password: 's3cret-pass' }).expect(200);
  const auth = { Authorization: `Bearer ${login.body.data.token}` };

  await t.test('requires a token', async () => {
    await request(app).get('/api/v1/sessions/strength').expect(401);
  });

  await t.test('no history is an empty series, not a 404', async () => {
    const get = await request(app).get('/api/v1/sessions/strength').set(auth).expect(200);
    assert.deepEqual(get.body.data.points, []);
    assert.deepEqual(get.body.data.options, []);
    assert.equal(get.body.data.exerciseId, null);
  });

  await t.test('with no exerciseId it picks the most-logged one', async () => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, 'completed', CURDATE())`, [userId],
    );
    for (let i = 1; i <= 3; i += 1) {
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
         VALUES (?, ?, ?, 60, ?, TRUE)`,
        [s.insertId, ex.exercise_id, i, 11 - i],
      );
    }

    const get = await request(app).get('/api/v1/sessions/strength').set(auth).expect(200);
    assert.equal(get.body.data.exerciseId, ex.exercise_id);
    assert.equal(get.body.data.xAxis, 'set', 'day one plots per set');
    assert.equal(get.body.data.points.length, 3);
    assert.equal(get.body.data.options[0].sets, 3);
  });

  await t.test('an unknown period is a 400', async () => {
    await request(app).get('/api/v1/sessions/strength?period=decade').set(auth).expect(400);
  });

  await t.test('a non-numeric exerciseId is a 400', async () => {
    await request(app).get('/api/v1/sessions/strength?exerciseId=abc').set(auth).expect(400);
  });
});
