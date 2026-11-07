'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

// The admin endpoints that suspend and reinstate come later (S2); here the
// column is set directly, which is all the sign-in paths read.
test('a suspended trainee', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const suspend = (userId) => pool.query('UPDATE users SET suspended_at = NOW() WHERE user_id = ?', [userId]);
  const reinstate = (userId) => pool.query('UPDATE users SET suspended_at = NULL WHERE user_id = ?', [userId]);
  const login = (email, password) => request(app).post('/api/v1/auth/login').send({ email, password });
  const isSuspended = (res) => {
    assert.equal(res.body.error.code, 'ACCOUNT_SUSPENDED');
    assert.equal(res.body.error.message, 'This account is suspended.');
  };

  let seq = 0;
  const trainee = async ({ verified = true } = {}) => {
    seq += 1;
    const email = `sus${seq}@example.com`;
    const reg = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'Sus' }).expect(201);
    const { userId } = reg.body.data.user;
    if (verified) await markEmailVerified(pool, userId);
    return { userId, email };
  };

  await t.test('sign-in with the right password is 403 ACCOUNT_SUSPENDED', async () => {
    const u = await trainee();
    await suspend(u.userId);
    isSuspended(await login(u.email, 's3cret-pass').expect(403));
  });

  await t.test('a wrong password is still the usual 401: the compare runs first', async () => {
    const u = await trainee();
    await suspend(u.userId);
    const res = await login(u.email, 'not-the-password').expect(401);
    assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
  });

  await t.test('suspended and unverified says suspended', async () => {
    const u = await trainee({ verified: false });
    await suspend(u.userId);
    isSuspended(await login(u.email, 's3cret-pass').expect(403));
  });

  await t.test('a token issued before the suspension stops working at once', async () => {
    const u = await trainee();
    const { token } = (await login(u.email, 's3cret-pass').expect(200)).body.data;
    const auth = { Authorization: `Bearer ${token}` };
    await request(app).get('/api/v1/auth/me').set(auth).expect(200);
    await suspend(u.userId);
    isSuspended(await request(app).get('/api/v1/auth/me').set(auth).expect(403));
    isSuspended(await request(app).get('/api/v1/profile').set(auth).expect(403));
  });

  await t.test('it says suspended even after the token generation moves on', async () => {
    const u = await trainee();
    const { token } = (await login(u.email, 's3cret-pass').expect(200)).body.data;
    // Suspending from the dashboard also moves token_version on (S2).
    await pool.query(
      'UPDATE users SET suspended_at = NOW(), token_version = token_version + 1 WHERE user_id = ?', [u.userId],
    );
    isSuspended(await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${token}`).expect(403));
  });

  await t.test('Google sign-in for a suspended Google account is 403', async () => {
    const first = await request(app).post('/api/v1/auth/google').send({ idToken: 'stub-token-maria' }).expect(200);
    await suspend(first.body.data.user.userId);
    isSuspended(await request(app).post('/api/v1/auth/google').send({ idToken: 'stub-token-maria' }).expect(403));
  });

  await t.test('reinstated, the trainee signs in again', async () => {
    const u = await trainee();
    await suspend(u.userId);
    await login(u.email, 's3cret-pass').expect(403);
    await reinstate(u.userId);
    const res = await login(u.email, 's3cret-pass').expect(200);
    assert.equal(res.body.data.role, 'trainee');
    await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${res.body.data.token}`).expect(200);
  });
});
