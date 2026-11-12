'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { signToken } = require('../src/lib/tokens');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

const JWT = { secret: 'test-secret-value-at-least-32-chars', expiresIn: '1h' };

test('change password', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });

  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const reset = async () => {
    await pool.query('DELETE FROM user_identities');
    await pool.query('DELETE FROM users');
  };

  /// A verified password account, plus a token for it from "another
  /// device", signed this very second: a change must sign it out even when
  /// both land in the same second.
  const passwordUser = async (email = 'juan@example.com', password = 's3cret-pass') => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password, fullName: 'Juan' }).expect(201);
    const { userId } = res.body.data.user;
    await markEmailVerified(pool, userId);
    return { userId, token: signToken(userId, JWT) };
  };

  const change = (token, body) => request(app).post('/api/v1/auth/password')
    .set('Authorization', `Bearer ${token}`).send(body);
  const me = (token) => request(app).get('/api/v1/auth/me')
    .set('Authorization', `Bearer ${token}`);
  const login = (email, password) =>
    request(app).post('/api/v1/auth/login').send({ email, password });

  await t.test('changes the password, returns a fresh token and signs out older ones', async () => {
    await reset();
    const { token: old } = await passwordUser();

    const res = await change(old, {
      currentPassword: 's3cret-pass', newPassword: 'a brand new pass',
    });
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(res.body.data), ['token']);
    assert.equal(typeof res.body.data.token, 'string');

    await me(res.body.data.token).expect(200);
    const stale = await me(old).expect(401);
    assert.equal(stale.body.error.code, 'UNAUTHENTICATED');

    assert.equal((await login('juan@example.com', 'a brand new pass')).status, 200);
    assert.equal((await login('juan@example.com', 's3cret-pass')).status, 401);
  });

  // Login and Google sign-in sign with the account's current generation, so
  // the tokens they hand out after a change work.
  await t.test('signing in again after a change, by password or Google, works', async () => {
    await reset();
    const { token } = await passwordUser();
    // Same address as the stub's Google identity: signing in links it.
    await request(app).post('/api/v1/auth/google')
      .send({ idToken: 'stub-token-juan' }).expect(200);
    await change(token, { currentPassword: 's3cret-pass', newPassword: 'a brand new pass' })
      .expect(200);

    const byPassword = await login('juan@example.com', 'a brand new pass').expect(200);
    await me(byPassword.body.data.token).expect(200);
    const byGoogle = await request(app).post('/api/v1/auth/google')
      .send({ idToken: 'stub-token-juan' }).expect(200);
    await me(byGoogle.body.data.token).expect(200);
  });

  await t.test('a wrong current password is WRONG_PASSWORD and changes nothing', async () => {
    await reset();
    const { token } = await passwordUser();

    const res = await change(token, {
      currentPassword: 'not-my-pass', newPassword: 'a brand new pass',
    });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'WRONG_PASSWORD');
    assert.equal(res.body.error.message, "That password isn't right.");

    await me(token).expect(200);
    assert.equal((await login('juan@example.com', 's3cret-pass')).status, 200);
  });

  await t.test('a Google-only account is NO_PASSWORD', async () => {
    await reset();
    const google = await request(app).post('/api/v1/auth/google')
      .send({ idToken: 'stub-token-juan' }).expect(200);

    const res = await change(google.body.data.token, {
      currentPassword: 'anything at all', newPassword: 'a brand new pass',
    });
    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'NO_PASSWORD');
    assert.equal(res.body.error.message,
      'This account signs in with Google and has no password.');

    const [rows] = await pool.query(
      'SELECT password_hash FROM users WHERE user_id = ?', [google.body.data.user.userId],
    );
    assert.equal(rows[0].password_hash, null, 'no password was set');
  });

  await t.test('the new password follows the register rule', async () => {
    await reset();
    const { token } = await passwordUser();

    for (const newPassword of ['short', 'a'.repeat(73), undefined, 12345678]) {
      const res = await change(token, { currentPassword: 's3cret-pass', newPassword });
      assert.equal(res.status, 400, String(newPassword));
      assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
      assert.deepEqual(res.body.error.details, [{ field: 'newPassword' }]);
    }

    await me(token).expect(200);
    assert.equal((await login('juan@example.com', 's3cret-pass')).status, 200);
  });

  // The contract has one answer for a current password that cannot be the
  // right one: WRONG_PASSWORD, which the app shows under the current-password
  // field. A missing, blank, non-string or over-length one is no different --
  // no stored password is blank or over 72 characters.
  await t.test('a missing, blank or over-length current password is WRONG_PASSWORD', async () => {
    await reset();
    const { token } = await passwordUser();

    const bodies = [
      {}, { currentPassword: '' }, { currentPassword: '   ' }, { currentPassword: null },
      { currentPassword: 12345678 }, { currentPassword: 'a'.repeat(73) },
    ];
    for (const body of bodies) {
      const res = await change(token, { ...body, newPassword: 'a brand new pass' });
      const label = JSON.stringify(body);
      assert.equal(res.status, 400, label);
      assert.equal(res.body.error.code, 'WRONG_PASSWORD', label);
      assert.equal(res.body.error.message, "That password isn't right.", label);
    }

    await me(token).expect(200);
    assert.equal((await login('juan@example.com', 's3cret-pass')).status, 200);
  });

  // Only a reset code proves the address; knowing the current password does
  // not, so a change leaves verification exactly as it was.
  await t.test('a change does not verify the address', async () => {
    await reset();
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'new@example.com', password: 's3cret-pass', fullName: 'N' })
      .expect(201);
    const { userId } = res.body.data.user;

    const done = await change(signToken(userId, JWT), {
      currentPassword: 's3cret-pass', newPassword: 'a brand new pass',
    });
    assert.equal(done.status, 200);
    const [[row]] = await pool.query(
      'SELECT email_verified FROM users WHERE user_id = ?', [userId],
    );
    assert.equal(row.email_verified, 0);
  });

  await t.test('requires a signed-in caller', async () => {
    const res = await request(app).post('/api/v1/auth/password')
      .send({ currentPassword: 's3cret-pass', newPassword: 'a brand new pass' });
    assert.equal(res.status, 401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });
});
