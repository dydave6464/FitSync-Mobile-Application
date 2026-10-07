'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

const CLEAR = { conditions: [], chestPain: false, dizziness: false, supervisedOnly: false };

test('health check endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `hc${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'H' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId: res.body.data.user.userId,
      get: () => request(app).get('/api/v1/profile/health').set(auth),
      put: (b) => request(app).put('/api/v1/profile/health').set(auth).send(b),
      del: () => request(app).delete('/api/v1/profile/health').set(auth),
    };
  };
  const rowCount = async (userId) => {
    const [[row]] = await pool.query(
      'SELECT COUNT(*) AS n FROM health_checks WHERE user_id = ?', [userId],
    );
    return Number(row.n);
  };

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/profile/health').expect(401);
    await request(app).put('/api/v1/profile/health').send(CLEAR).expect(401);
    await request(app).delete('/api/v1/profile/health').expect(401);
  });

  await t.test('a new account has no health check', async () => {
    const u = await freshUser();
    const res = await u.get().expect(200);
    assert.deepEqual(res.body, { data: { health: null } });
  });

  await t.test('a clear check is stored with no consent stamps', async () => {
    const u = await freshUser();
    const res = await u.put(CLEAR).expect(200);
    assert.deepEqual(res.body.data.health, {
      ...CLEAR, consentedAt: null, acknowledgedAt: null,
    });
    assert.deepEqual((await u.get().expect(200)).body.data.health, res.body.data.health);
    assert.equal(await rowCount(u.userId), 1);
  });

  await t.test('a positive check without consent is refused and nothing is stored', async () => {
    const u = await freshUser();
    const res = await u.put({ ...CLEAR, conditions: ['asthma'], acknowledged: true }).expect(400);
    assert.equal(res.body.error.code, 'HEALTH_CONSENT_REQUIRED');
    assert.equal(await rowCount(u.userId), 0);
  });

  await t.test('a positive check without the acknowledgement is refused', async () => {
    const u = await freshUser();
    const res = await u.put({ ...CLEAR, chestPain: true, consent: true }).expect(400);
    assert.equal(res.body.error.code, 'HEALTH_ACK_REQUIRED');
    assert.equal(await rowCount(u.userId), 0);
  });

  await t.test('a positive check is stamped and read back in card order', async () => {
    const u = await freshUser();
    const res = await u.put({
      ...CLEAR,
      conditions: ['diabetes', 'high_blood_pressure'],
      dizziness: true,
      consent: true,
      acknowledged: true,
    }).expect(200);
    const { health } = res.body.data;
    assert.deepEqual(health.conditions, ['high_blood_pressure', 'diabetes']);
    assert.equal(health.dizziness, true);
    assert.equal(health.chestPain, false);
    assert.match(health.consentedAt, /^\d{4}-\d{2}-\d{2}T/);
    assert.match(health.acknowledgedAt, /^\d{4}-\d{2}-\d{2}T/);
  });

  await t.test('invalid bodies name the field', async () => {
    const u = await freshUser();
    for (const [body, field] of [
      [{ ...CLEAR, conditions: 'asthma' }, 'conditions'],
      [{ ...CLEAR, conditions: ['flu'] }, 'conditions'],
      [{ ...CLEAR, conditions: ['asthma', 'asthma'], consent: true, acknowledged: true }, 'conditions'],
      [{ conditions: [], chestPain: false, supervisedOnly: false }, 'dizziness'],
      [{ ...CLEAR, chestPain: 'no' }, 'chestPain'],
      [{ ...CLEAR, supervisedOnly: null }, 'supervisedOnly'],
    ]) {
      const res = await u.put(body).expect(400);
      assert.equal(res.body.error.code, 'INVALID_HEALTH_FIELD', JSON.stringify(body));
      assert.equal(res.body.error.details[0].field, field, JSON.stringify(body));
    }
    assert.equal(await rowCount(u.userId), 0);
  });

  await t.test('a second save replaces the first', async () => {
    const u = await freshUser();
    await u.put({ ...CLEAR, conditions: ['asthma'], consent: true, acknowledged: true }).expect(200);
    const res = await u.put(CLEAR).expect(200);
    assert.deepEqual(res.body.data.health, { ...CLEAR, consentedAt: null, acknowledgedAt: null });
    assert.equal(await rowCount(u.userId), 1);
  });

  await t.test('delete removes the answers, and deleting again is harmless', async () => {
    const u = await freshUser();
    await u.put({ ...CLEAR, conditions: ['other'], consent: true, acknowledged: true }).expect(200);
    assert.deepEqual((await u.del().expect(200)).body, { data: { health: null } });
    assert.deepEqual((await u.get().expect(200)).body, { data: { health: null } });
    await u.del().expect(200);
    assert.equal(await rowCount(u.userId), 0);
  });

  await t.test('the answers go with their user', async () => {
    const u = await freshUser();
    await u.put(CLEAR).expect(200);
    await pool.query('DELETE FROM users WHERE user_id = ?', [u.userId]);
    assert.equal(await rowCount(u.userId), 0);
  });
});
