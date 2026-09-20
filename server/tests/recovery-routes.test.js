'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

const ANSWERS = {
  sleepQuality: 'poor',
  muscleSoreness: 'severe',
  energy: 'low',
  stress: 'high',
};

/// Records what the route sent, and answers like the real estimator would.
function recordingMl() {
  const calls = [];
  return {
    calls,
    async estimateInjuryRisk(payload) {
      calls.push(payload);
      return { riskLevel: 'moderate', trainingLoadScore: 42.5 };
    },
  };
}

test('recovery routes', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const ml = recordingMl();
  const app = buildTestApp({ pool, ml });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const reg = await request(app).post('/api/v1/auth/register')
    .send({ email: 'rec@example.com', password: 's3cret-pass', fullName: 'R' })
    .expect(201);
  await markEmailVerified(pool, reg.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'rec@example.com', password: 's3cret-pass' }).expect(200);
  const auth = { Authorization: `Bearer ${login.body.data.token}` };

  await t.test('requires a token', async () => {
    await request(app).get('/api/v1/recovery').expect(401);
    await request(app).post('/api/v1/recovery/checkin').send(ANSWERS).expect(401);
  });

  await t.test('an empty tab answers nulls, not an error', async () => {
    const res = await request(app).get('/api/v1/recovery').set(auth).expect(200);
    assert.equal(res.body.data.todayCheckin, null);
    assert.equal(res.body.data.latestEstimate, null);
    assert.equal(res.body.data.load.length, 7);
  });

  await t.test('a bad answer is a 400 naming the field', async () => {
    const res = await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send({ ...ANSWERS, energy: 'fantastic' }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_CHECKIN');
    assert.match(res.body.error.message, /energy/);
  });

  await t.test('a missing answer is a 400 naming the field', async () => {
    const body = { ...ANSWERS };
    delete body.stress;
    const res = await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(body).expect(400);
    assert.equal(res.body.error.code, 'INVALID_CHECKIN');
    assert.match(res.body.error.message, /stress/);
  });

  await t.test('a check-in stores an estimate against itself', async () => {
    const post = await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);

    assert.equal(post.body.data.estimate.riskLevel, 'moderate');
    assert.equal(post.body.data.checkin.sleepQuality, 'poor');

    const [[row]] = await pool.query(
      `SELECT e.risk_level, e.checkin_id, c.checkin_date
         FROM injury_risk_estimates e
         JOIN morning_checkins c ON c.checkin_id = e.checkin_id`,
    );
    assert.equal(row.risk_level, 'moderate');
    assert.equal(row.checkin_id, post.body.data.checkin.checkinId);
  });

  await t.test('the ML service is sent the spellings risk.py looks up',
    async () => {
      const payload = ml.calls.at(-1);
      // Asserted on the values, not just that a call happened: risk.py reads
      // these with .get(value, 0.0), so a wrong spelling scores zero penalty
      // and raises nothing.
      assert.equal(payload.checkins[0].sleepQuality, 'poor');
      assert.equal(payload.checkins[0].muscleSoreness, 'severe');
      assert.equal(typeof payload.load, 'number');
      assert.ok(Number.isFinite(payload.load));
    });

  await t.test('the tab then serves the stored estimate and its date',
    async () => {
      const res = await request(app).get('/api/v1/recovery').set(auth).expect(200);
      assert.equal(res.body.data.latestEstimate.riskLevel, 'moderate');
      assert.equal(res.body.data.latestEstimate.trainingLoadScore, 42.5);
      assert.match(res.body.data.latestEstimate.checkinDate, /^\d{4}-\d{2}-\d{2}$/);
      assert.equal(res.body.data.todayCheckin.energy, 'low');
    });

  await t.test('a second check-in the same day updates it', async () => {
    await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send({ ...ANSWERS, energy: 'high' }).expect(201);

    const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM morning_checkins');
    assert.equal(n, 1, 'one row per day');

    const [[{ e }]] = await pool.query('SELECT COUNT(*) AS e FROM injury_risk_estimates');
    assert.equal(e, 2, 'estimates are append-only');
  });
});

test('recovery survives the ML service being down', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({
    pool,
    ml: {
      async estimateInjuryRisk() { throw new Error('ECONNREFUSED'); },
    },
  });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const reg = await request(app).post('/api/v1/auth/register')
    .send({ email: 'down@example.com', password: 's3cret-pass', fullName: 'D' })
    .expect(201);
  await markEmailVerified(pool, reg.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'down@example.com', password: 's3cret-pass' }).expect(200);

  // The check-in is the user's own data. Losing it because a service is down
  // would be the worse failure, so the route falls back to the same floor the
  // stub returns everywhere else.
  const post = await request(app).post('/api/v1/recovery/checkin')
    .set('Authorization', `Bearer ${login.body.data.token}`)
    .send(ANSWERS).expect(201);

  assert.equal(post.body.data.estimate.riskLevel, 'low');
  assert.equal(post.body.data.estimate.trainingLoadScore, 0);

  const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM morning_checkins');
  assert.equal(n, 1);
});
