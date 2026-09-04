'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('auth endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const reset = async () => {
    await pool.query('DELETE FROM user_identities');
    await pool.query('DELETE FROM users');
  };

  const register = () => request(app).post('/api/v1/auth/register').send({
    email: 'juan@example.com', password: 's3cret-pass', fullName: 'Juan Dela Cruz',
  });

  await t.test('registers with no token and an unverified account', async () => {
    await reset();
    const res = await register().expect(201);
    assert.equal(res.body.data.user.email, 'juan@example.com');
    // Hard gate: registration proves nothing about the address yet, so no
    // session is issued until the verification link is followed.
    assert.equal(res.body.data.token, undefined);
    assert.equal(res.body.data.user.emailVerified, false);
    // A vacuous form of this assertion — checking only that passwordHash (the
    // camelCase name) is undefined — would still pass if toPublicUser were
    // ever replaced by a naive spread of the database row, which carries the
    // hash under its actual key, password_hash. Pinning the full key set (and
    // separately confirming password_hash by name) is what actually catches
    // that regression.
    assert.deepEqual(
      Object.keys(res.body.data.user).sort(),
      ['email', 'emailVerified', 'fullName', 'isPremium', 'onboardingCompleted', 'userId'].sort(),
    );
    assert.ok(
      !Object.prototype.hasOwnProperty.call(res.body.data.user, 'password_hash'),
      'never leak the hash',
    );
  });

  await t.test('rejects a duplicate email', async () => {
    await reset();
    await register().expect(201);
    const res = await register().expect(409);
    assert.equal(res.body.error.code, 'EMAIL_TAKEN');
  });

  await t.test('rejects a short password', async () => {
    await reset();
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'a@b.com', password: 'short', fullName: 'A' }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  // users.email is VARCHAR(255). Without a max-length check this reaches
  // pool.query and MySQL raises ER_DATA_TOO_LONG, which the generic handler
  // turns into a 500 — a 400 belongs here instead.
  await t.test('rejects an email longer than the column allows', async () => {
    await reset();
    const overlong = `${'a'.repeat(250)}@b.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: overlong, password: 's3cret-pass', fullName: 'A' }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  // users.full_name is VARCHAR(255) — same hazard as email above.
  await t.test('rejects a full name longer than the column allows', async () => {
    await reset();
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'longname@b.com', password: 's3cret-pass', fullName: 'a'.repeat(256) })
      .expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  // bcrypt only reads the first 72 bytes of its input; anything past that adds
  // no security and an unbounded password is a cheap way to make the server
  // spend real CPU on a deliberately slow hash function.
  await t.test('rejects a password longer than bcrypt can use', async () => {
    await reset();
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'longpass@b.com', password: 'a'.repeat(73), fullName: 'A' })
      .expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  await t.test('logs in with the right password', async () => {
    await reset();
    const registered = await register().expect(201);
    // Registration alone no longer grants sign-in; prove the address the way
    // production does, by consuming the mailed link, not by reaching past the
    // gate under test.
    await markEmailVerified(pool, registered.body.data.user.userId);
    const res = await request(app).post('/api/v1/auth/login')
      .send({ email: 'juan@example.com', password: 's3cret-pass' }).expect(200);
    assert.ok(res.body.data.token);
  });

  await t.test('gives the same error for a wrong password and an unknown email', async () => {
    await reset();
    await register().expect(201);
    const wrong = await request(app).post('/api/v1/auth/login')
      .send({ email: 'juan@example.com', password: 'nope' }).expect(401);
    const unknown = await request(app).post('/api/v1/auth/login')
      .send({ email: 'nobody@example.com', password: 'nope' }).expect(401);
    assert.equal(wrong.body.error.code, 'INVALID_CREDENTIALS');
    assert.equal(unknown.body.error.code, 'INVALID_CREDENTIALS');
    assert.equal(wrong.body.error.message, unknown.body.error.message,
      'the messages must not distinguish the two');
  });

  await t.test('signs in with Google and reports a new user', async () => {
    await reset();
    const res = await request(app).post('/api/v1/auth/google')
      .send({ idToken: 'stub-token-juan' }).expect(200);
    assert.equal(res.body.data.isNewUser, true);
    assert.ok(res.body.data.token);
  });

  await t.test('rejects an unverifiable Google token', async () => {
    await reset();
    const res = await request(app).post('/api/v1/auth/google')
      .send({ idToken: 'nonsense' }).expect(401);
    assert.equal(res.body.error.code, 'INVALID_GOOGLE_TOKEN');
  });

  // Distinct from the case above: this token IS recognized by the verifier
  // (unlike 'nonsense', which the stub itself rejects before
  // findOrCreateGoogleUser ever runs) but carries emailVerified: false. This
  // is what actually exercises the Task 6 pre-hijacking gate through the HTTP
  // layer — if that gate ever moved back inside the account-linking branch,
  // this is the test that would catch it.
  await t.test('refuses an unverified Google identity and creates no account', async () => {
    await reset();
    const res = await request(app).post('/api/v1/auth/google')
      .send({ idToken: 'stub-token-unverified' }).expect(401);
    assert.equal(res.body.error.code, 'INVALID_GOOGLE_TOKEN');

    const [rows] = await pool.query('SELECT * FROM users');
    assert.equal(rows.length, 0, 'the gate must hold before any row is written');
  });

  await t.test('me returns the signed-in user', async () => {
    await reset();
    const { body } = await register().expect(201);
    await markEmailVerified(pool, body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'juan@example.com', password: 's3cret-pass' }).expect(200);
    const res = await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${login.body.data.token}`).expect(200);
    assert.equal(res.body.data.user.email, 'juan@example.com');
    assert.equal(res.body.data.user.onboardingCompleted, false);
  });
});
