'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('training settings endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `ts${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'T' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId: res.body.data.user.userId,
      get: () => request(app).get('/api/v1/training/settings').set(auth),
      patch: (b) => request(app).patch('/api/v1/training/settings').set(auth).send(b),
    };
  };

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/training/settings').expect(401);
    await request(app).patch('/api/v1/training/settings').send({}).expect(401);
  });

  await t.test('a new account reads the 90-second default without a row', async () => {
    const u = await freshUser();
    const res = await u.get().expect(200);
    assert.deepEqual(res.body, { data: { settings: { restSeconds: 90 } } });
    const [rows] = await pool.query(
      'SELECT COUNT(*) AS n FROM training_settings WHERE user_id = ?', [u.userId],
    );
    assert.equal(rows[0].n, 0);
  });

  await t.test('a rest time is saved and read back; unknown keys are dropped', async () => {
    const u = await freshUser();
    const res = await u.patch({ restSeconds: 150, surprise: 1 }).expect(200);
    assert.deepEqual(res.body, { data: { settings: { restSeconds: 150 } } });
    assert.equal((await u.get().expect(200)).body.data.settings.restSeconds, 150);
    // A second write updates the same row rather than adding one.
    await u.patch({ restSeconds: 45 }).expect(200);
    assert.equal((await u.get().expect(200)).body.data.settings.restSeconds, 45);
  });

  await t.test('the bounds the app offers are accepted', async () => {
    const u = await freshUser();
    await u.patch({ restSeconds: 10 }).expect(200);
    await u.patch({ restSeconds: 600 }).expect(200);
  });

  await t.test('out-of-range or non-whole values are refused with a named code', async () => {
    const u = await freshUser();
    for (const body of [
      { restSeconds: 9 },
      { restSeconds: 601 },
      { restSeconds: 90.5 },
      { restSeconds: '90' },
      { restSeconds: null },
    ]) {
      const res = await u.patch(body).expect(400);
      assert.equal(res.body.error.code, 'REST_INVALID', JSON.stringify(body));
    }
    assert.equal((await u.get().expect(200)).body.data.settings.restSeconds, 90);
  });

  await t.test('one account cannot see another\'s rest time', async () => {
    const a = await freshUser();
    const b = await freshUser();
    await a.patch({ restSeconds: 240 }).expect(200);
    assert.equal((await b.get().expect(200)).body.data.settings.restSeconds, 90);
  });
});
