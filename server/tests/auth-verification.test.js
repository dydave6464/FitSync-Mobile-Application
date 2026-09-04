'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createMailService } = require('../src/services/mail');
const { findUserByEmail } = require('../src/db/users');

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
    // This link arrives by email and is opened straight in a browser -- a
    // stale or reused link (expired, already used, mistyped) must fail into
    // a page, not the JSON error envelope the JSON API uses everywhere else.
    assert.match(page.headers['content-type'], /html/,
      'a browser-facing route must fail into a page, not a JSON error object');
    assert.doesNotMatch(page.text, /^\s*\{/, 'must not be a raw JSON error object');
  });

  await t.test('a resend requires the password, and is quiet either way', async () => {
    // gate@example.com is already verified by this point in the file, so
    // ok && !user.email_verified is false on both calls below -- this only
    // exercises the no-op path. See the next test for the actual send.
    const good = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'gate@example.com', password: 'correct horse' });
    const bad = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'gate@example.com', password: 'wrong' });
    assert.equal(good.status, 202);
    assert.equal(bad.status, 202);
    assert.deepEqual(good.body, bad.body);
  });

  await t.test('a correct-credential resend on a still-unverified account actually sends a link', async () => {
    // Under a hard gate this is the only recovery path for a user whose
    // first verification email was lost, so the route must actually send
    // one -- a fresh, still-unverified account is required to exercise that
    // branch at all; gate@example.com above cannot, once verified.
    await request(app).post('/api/v1/auth/register').send({
      email: 'resend@example.com', password: 'correct horse battery', fullName: 'Resend Me',
    });
    const before = mail.sent.length;

    const good = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'resend@example.com', password: 'correct horse battery' });
    const bad = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'resend@example.com', password: 'wrong' });

    assert.equal(good.status, 202);
    assert.equal(bad.status, 202);
    assert.equal(good.text, bad.text,
      'must stay indistinguishable by credential correctness even while actually sending');

    const resent = mail.sent.slice(before);
    assert.equal(resent.length, 1, 'only the correct-credential call should have sent anything');
    assert.match(resent[0].text, /\/auth\/verify-email\?token=[a-f0-9]{64}/);
  });

  await t.test('an unparseable email is refused outright', async () => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'notanemail', password: 'correct horse', fullName: 'X' });
    assert.equal(res.status, 400);
  });

  await t.test('registration survives a mail outage', async () => {
    // Spec section 10: a mail outage must not make accounts uncreatable. The
    // try/catch inside sendVerification is the mechanism -- this is what
    // proves it actually works, on a fresh app instance (sharing the same
    // pool) wired to a mail double whose send always rejects.
    const failingMail = { send: async () => { throw new Error('smtp is down'); } };
    const failingApp = buildTestApp({ pool, mail: failingMail });

    const res = await request(failingApp).post('/api/v1/auth/register').send({
      email: 'outage@example.com', password: 'correct horse', fullName: 'Outage',
    });
    assert.equal(res.status, 201, 'a mail outage must not fail registration');

    const user = await findUserByEmail(pool, 'outage@example.com');
    assert.ok(user, 'the user row must still be created');

    const [tokens] = await pool.query(
      "SELECT * FROM auth_tokens WHERE user_id = ? AND purpose = 'verify_email'",
      [user.user_id],
    );
    assert.equal(tokens.length, 1, 'the verify_email token must still be issued');
  });
});
