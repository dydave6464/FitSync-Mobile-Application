'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { markEmailVerified } = require('../src/db/users');

test('session outcome endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());
  const app = buildTestApp({ pool });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const [knee] = await pool.query("SELECT injury_id FROM injuries WHERE name = 'Knee'");
  const kneeId = knee[0].injury_id;

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `outcome${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'W' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { token: login.body.data.token, userId: res.body.data.user.userId };
  };

  const session = async (userId, { daysAgo = 1, status = 'completed' } = {}) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, ?, CURDATE() - INTERVAL ? DAY)`,
      [userId, status, daysAgo],
    );
    return s.insertId;
  };

  const post = (token, sessionId, body) => request(app)
    .post(`/api/v1/sessions/${sessionId}/outcome`)
    .set('Authorization', `Bearer ${token}`)
    .send(body);

  await t.test('pending is null for an account that has not trained', async () => {
    const { token } = await freshUser();
    const res = await request(app).get('/api/v1/sessions/pending-outcome')
      .set('Authorization', `Bearer ${token}`).expect(200);
    assert.deepEqual(res.body, { data: { session: null } });
  });

  await t.test('pending names the last session until it is answered', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);

    const before = await request(app).get('/api/v1/sessions/pending-outcome')
      .set('Authorization', `Bearer ${token}`).expect(200);
    assert.equal(before.body.data.session.sessionId, sessionId);
    assert.match(before.body.data.session.sessionDate, /^\d{4}-\d{2}-\d{2}$/);
    assert.equal(before.body.data.session.planName, null);

    await post(token, sessionId, { painLevel: 'none' }).expect(201);

    const after = await request(app).get('/api/v1/sessions/pending-outcome')
      .set('Authorization', `Bearer ${token}`).expect(200);
    assert.equal(after.body.data.session, null);
  });

  await t.test('pending requires a signed-in user', async () => {
    await request(app).get('/api/v1/sessions/pending-outcome').expect(401);
  });

  await t.test('stores no pain', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);
    const res = await post(token, sessionId, { painLevel: 'none' }).expect(201);
    assert.equal(res.body.data.outcome.sessionId, sessionId);
    assert.equal(res.body.data.outcome.painLevel, 'none');
    assert.equal(res.body.data.outcome.injuryId, null);
  });

  await t.test('an explicit null region reads as no region', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);
    await post(token, sessionId, { painLevel: 'none', injuryId: null }).expect(201);
  });

  await t.test('stores pain with its region', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);
    const res = await post(token, sessionId, { painLevel: 'moderate', injuryId: kneeId }).expect(201);
    assert.equal(res.body.data.outcome.injuryId, kneeId);
  });

  await t.test('rejects a pain level it does not know', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);
    for (const painLevel of [undefined, 'NONE', 'sore', 3]) {
      const res = await post(token, sessionId, { painLevel }).expect(400);
      assert.equal(res.body.error.code, 'PAIN_LEVEL_INVALID', `painLevel ${painLevel}`);
    }
  });

  await t.test('rejects a region alongside no pain', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);
    const res = await post(token, sessionId, { painLevel: 'none', injuryId: kneeId }).expect(400);
    assert.equal(res.body.error.code, 'INJURY_NOT_EXPECTED');
  });

  await t.test('rejects pain without a region', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);
    const res = await post(token, sessionId, { painLevel: 'mild' }).expect(400);
    assert.equal(res.body.error.code, 'INJURY_REQUIRED');
  });

  await t.test('rejects a region that is not a body region', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);
    for (const injuryId of ['7', 0, -1, 1.5, 999999]) {
      const res = await post(token, sessionId, { painLevel: 'mild', injuryId }).expect(400);
      assert.equal(res.body.error.code, 'INJURY_INVALID', `injuryId ${injuryId}`);
    }
  });

  await t.test("another user's session is not found", async () => {
    const owner = await freshUser();
    const intruder = await freshUser();
    const sessionId = await session(owner.userId);
    const res = await post(intruder.token, sessionId, { painLevel: 'none' }).expect(404);
    assert.equal(res.body.error.code, 'SESSION_NOT_FOUND');
  });

  await t.test('a session still in progress is not found', async () => {
    const { token, userId } = await freshUser();
    const open = await session(userId, { status: 'in_progress', daysAgo: 0 });
    await post(token, open, { painLevel: 'none' }).expect(404);
  });

  await t.test('a non-numeric session id is not found', async () => {
    const { token } = await freshUser();
    await post(token, 'abc', { painLevel: 'none' }).expect(404);
  });

  await t.test('a double submit is a conflict', async () => {
    const { token, userId } = await freshUser();
    const sessionId = await session(userId);
    await post(token, sessionId, { painLevel: 'none' }).expect(201);
    const res = await post(token, sessionId, { painLevel: 'none' }).expect(409);
    assert.equal(res.body.error.code, 'OUTCOME_EXISTS');
  });
});
