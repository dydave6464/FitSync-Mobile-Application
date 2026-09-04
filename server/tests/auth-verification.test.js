'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createMailService } = require('../src/services/mail');

test('email verification gate', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const mail = createMailService({ mode: 'stub' });
  const app = buildTestApp({ pool, mail });

  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const register = () => request(app).post('/api/v1/auth/register').send({
    email: 'gate@example.com', password: 'correct horse', fullName: 'Gate',
  });

  await t.test('registration issues no token', async () => {
    const res = await register();
    assert.equal(res.status, 201);
    assert.equal(res.body.data.token, undefined,
      'a hard gate means no session until the address is proven');
    assert.equal(res.body.data.user.emailVerified, false);
  });

  await t.test('registration mails a verification link', async () => {
    assert.equal(mail.sent.length, 1);
    assert.match(mail.sent[0].text, /\/auth\/verify-email\?token=[a-f0-9]{64}/);
  });

  await t.test('an unverified account cannot sign in', async () => {
    const res = await request(app).post('/api/v1/auth/login')
      .send({ email: 'gate@example.com', password: 'correct horse' });
    assert.equal(res.status, 403);
    assert.equal(res.body.error.code, 'EMAIL_NOT_VERIFIED');
  });

  await t.test('a wrong password on an unverified account still says INVALID_CREDENTIALS', async () => {
    // The verified check runs AFTER the password compare, so a wrong password
    // never reveals that the address is registered.
    const res = await request(app).post('/api/v1/auth/login')
      .send({ email: 'gate@example.com', password: 'wrong' });
    assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
  });

  await t.test('following the link verifies and then sign-in works', async () => {
    const token = mail.sent[0].text.match(/token=([a-f0-9]{64})/)[1];
    const page = await request(app).get(`/api/v1/auth/verify-email?token=${token}`);
    assert.equal(page.status, 200);
    assert.match(page.headers['content-type'], /html/);

    const res = await request(app).post('/api/v1/auth/login')
      .send({ email: 'gate@example.com', password: 'correct horse' });
    assert.equal(res.status, 200);
    assert.ok(res.body.data.token);
    assert.equal(res.body.data.user.emailVerified, true);
  });

  await t.test('the link cannot be used twice', async () => {
    const token = mail.sent[0].text.match(/token=([a-f0-9]{64})/)[1];
    const page = await request(app).get(`/api/v1/auth/verify-email?token=${token}`);
    assert.equal(page.status, 400);
  });

  await t.test('a resend requires the password, and is quiet either way', async () => {
    const good = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'gate@example.com', password: 'correct horse' });
    const bad = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'gate@example.com', password: 'wrong' });
    assert.equal(good.status, 202);
    assert.equal(bad.status, 202);
    assert.deepEqual(good.body, bad.body);
  });

  await t.test('an unparseable email is refused outright', async () => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'notanemail', password: 'correct horse', fullName: 'X' });
    assert.equal(res.status, 400);
  });
});
