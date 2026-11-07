'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createTestAdmin } = require('./helpers/admin');
const { markEmailVerified } = require('../src/db/users');
const { IDENTITIES } = require('../src/services/google/stub');

test('admin sign-in on the normal sign-in form', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const login = (email, password) => request(app).post('/api/v1/auth/login').send({ email, password });
  const admin = await createTestAdmin(pool, {
    email: 'ada@fitsync.test', fullName: 'Ada Admin', password: 'admin-pass-123',
  });

  // Unit test 16 (manuscript): admin sign-in opens the overview.
  await t.test('admin sign-in opens the overview: the login token is accepted by GET /admin/me', async () => {
    const res = await login('ada@fitsync.test', 'admin-pass-123').expect(200);
    const { token } = res.body.data;
    assert.equal(typeof token, 'string');
    assert.deepEqual(res.body, {
      data: {
        role: 'admin',
        admin: { id: admin.adminId, email: 'ada@fitsync.test', fullName: 'Ada Admin' },
        token,
      },
    });
    const me = await request(app).get('/api/v1/admin/me')
      .set('Authorization', `Bearer ${token}`).expect(200);
    assert.deepEqual(me.body, {
      data: { admin: { id: admin.adminId, email: 'ada@fitsync.test', fullName: 'Ada Admin' } },
    });
  });

  await t.test('the admin email is matched in any case', async () => {
    const res = await login('ADA@FitSync.test', 'admin-pass-123').expect(200);
    assert.equal(res.body.data.role, 'admin');
  });

  await t.test('an admin with the wrong password gets the same 401 as a trainee', async () => {
    const wrong = await login('ada@fitsync.test', 'not-the-password').expect(401);
    const unknown = await login('nobody@fitsync.test', 'not-the-password').expect(401);
    assert.deepEqual(wrong.body.error, unknown.body.error);
    assert.equal(wrong.body.error.code, 'INVALID_CREDENTIALS');
    assert.equal(wrong.body.error.message, 'Email or password is incorrect.');
  });

  await t.test("the login token is refused on the trainee's GET /auth/me", async () => {
    const { token } = (await login('ada@fitsync.test', 'admin-pass-123').expect(200)).body.data;
    const res = await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${token}`).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test("a trainee's sign-in says role trainee beside user and token", async () => {
    const reg = await request(app).post('/api/v1/auth/register')
      .send({ email: 'juan.trainee@example.com', password: 's3cret-pass', fullName: 'Juan' }).expect(201);
    await markEmailVerified(pool, reg.body.data.user.userId);
    const res = await login('juan.trainee@example.com', 's3cret-pass').expect(200);
    assert.deepEqual(Object.keys(res.body.data).sort(), ['role', 'token', 'user']);
    assert.equal(res.body.data.role, 'trainee');
    assert.equal(res.body.data.user.email, 'juan.trainee@example.com');
    const me = await request(app).get('/api/v1/admin/me')
      .set('Authorization', `Bearer ${res.body.data.token}`).expect(401);
    assert.equal(me.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test("registering with an admin's email is EMAIL_TAKEN", async () => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'Ada@FITSYNC.test', password: 's3cret-pass', fullName: 'Not Ada' }).expect(409);
    assert.equal(res.body.error.code, 'EMAIL_TAKEN');
    assert.equal(res.body.error.message, 'That email is already registered.');
    const [rows] = await pool.query("SELECT 1 FROM users WHERE LOWER(email) = 'ada@fitsync.test'");
    assert.equal(rows.length, 0);
  });

  await t.test("Google sign-in with an admin's email is EMAIL_TAKEN and creates no trainee", async () => {
    const juan = IDENTITIES['stub-token-juan'];
    await createTestAdmin(pool, { email: juan.email, fullName: 'Juan Admin' });
    const res = await request(app).post('/api/v1/auth/google')
      .send({ idToken: 'stub-token-juan' }).expect(409);
    assert.equal(res.body.error.code, 'EMAIL_TAKEN');
    assert.equal(res.body.error.message, 'That email is already registered.');
    const [users] = await pool.query('SELECT 1 FROM users WHERE LOWER(email) = LOWER(?)', [juan.email]);
    assert.equal(users.length, 0);
    const [identities] = await pool.query("SELECT 1 FROM user_identities WHERE provider_subject = ?", [juan.subject]);
    assert.equal(identities.length, 0);
  });
});
