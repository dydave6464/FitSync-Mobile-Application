'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

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

  await t.test('registers and returns a token', async () => {
    await reset();
    const res = await register().expect(201);
    assert.equal(res.body.data.user.email, 'juan@example.com');
    assert.ok(res.body.data.token);
    assert.equal(res.body.data.user.passwordHash, undefined, 'never leak the hash');
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

  await t.test('logs in with the right password', async () => {
    await reset();
    await register().expect(201);
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

  await t.test('me returns the signed-in user', async () => {
    await reset();
    const { body } = await register().expect(201);
    const res = await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${body.data.token}`).expect(200);
    assert.equal(res.body.data.user.email, 'juan@example.com');
    assert.equal(res.body.data.user.onboardingCompleted, false);
  });
});
