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

/// The code from an email's subject line, "Your FitSync code: 048213".
const codeIn = (message) => message.subject.match(/(\d{6})$/)[1];

test('email verification gate', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const mail = createMailService({ mode: 'stub' });
  const app = buildTestApp({ pool, mail });

  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const register = (email = 'gate@example.com', password = 'correct horse') =>
    request(app).post('/api/v1/auth/register').send({ email, password, fullName: 'Gate' });
  const verify = (email, code) =>
    request(app).post('/api/v1/auth/verify-email').send({ email, code });
  const lastCode = (email) => codeIn(mail.sent.filter((m) => m.to === email).at(-1));
  const other = (code) => (code === '000000' ? '111111' : '000000');
  const ageCode = async (email) => {
    const user = await findUserByEmail(pool, email);
    await pool.query(
      'UPDATE auth_codes SET created_at = DATE_SUB(NOW(), INTERVAL 2 MINUTE) WHERE user_id = ?',
      [user.user_id],
    );
  };

  await t.test('registration issues no token', async () => {
    const res = await register();
    assert.equal(res.status, 201);
    assert.equal(res.body.data.token, undefined,
      'a hard gate means no session until the address is proven');
    assert.equal(res.body.data.user.emailVerified, false);
  });

  await t.test('registration mails a six-digit code and no link', async () => {
    const [m] = mail.sent.filter((x) => x.to === 'gate@example.com');
    assert.match(m.subject, /^Your FitSync code: \d{6}$/);
    assert.ok(m.text.includes(codeIn(m)), 'the code is in the body too');
    assert.doesNotMatch(m.text, /https?:\/\//, 'no link: the code is typed into the app');
    assert.match(m.text, /60 minutes/);
  });

  await t.test('an unverified account cannot sign in', async () => {
    const res = await request(app).post('/api/v1/auth/login')
      .send({ email: 'gate@example.com', password: 'correct horse' });
    assert.equal(res.status, 403);
    assert.equal(res.body.error.code, 'EMAIL_NOT_VERIFIED');
  });

  await t.test('a wrong password on an unverified account still says INVALID_CREDENTIALS', async () => {
    const res = await request(app).post('/api/v1/auth/login')
      .send({ email: 'gate@example.com', password: 'wrong' });
    assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
  });

  await t.test('every wrong answer looks exactly the same', async () => {
    const good = lastCode('gate@example.com');
    const responses = [
      await verify('gate@example.com', other(good)),
      await verify('nobody@example.com', good),
      await verify('gate@example.com', '12345'),
      await verify('gate@example.com', 'abcdef'),
      await verify('gate@example.com', undefined),
      await verify(undefined, good),
    ];
    for (const r of responses) {
      assert.equal(r.status, 400);
      assert.equal(r.body.error.code, 'CODE_INVALID');
    }
    assert.equal(new Set(responses.map((r) => r.text)).size, 1,
      'any difference would tell a stranger which accounts exist');
  });

  await t.test('the right code verifies, and then sign-in works', async () => {
    const res = await verify('gate@example.com', lastCode('gate@example.com'));
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { data: { verified: true } });

    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'gate@example.com', password: 'correct horse' });
    assert.equal(login.status, 200);
    assert.ok(login.body.data.token);
    assert.equal(login.body.data.user.emailVerified, true);
  });

  await t.test('a used code, or any code once verified, is CODE_INVALID', async () => {
    const res = await verify('gate@example.com', lastCode('gate@example.com'));
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'CODE_INVALID');
  });

  await t.test('a pasted code with spaces is accepted', async () => {
    await register('spaced@example.com');
    const code = lastCode('spaced@example.com');
    const res = await verify('spaced@example.com', ` ${code.slice(0, 3)} ${code.slice(3)} `);
    assert.equal(res.status, 200);
  });

  await t.test('five wrong tries use the code up', async () => {
    await register('guess@example.com');
    const good = lastCode('guess@example.com');
    for (let i = 0; i < 5; i += 1) {
      assert.equal((await verify('guess@example.com', other(good))).status, 400);
    }
    assert.equal((await verify('guess@example.com', good)).status, 400,
      'after five misses even the right code is dead');
  });

  await t.test('an expired code fails', async () => {
    await register('late@example.com');
    const good = lastCode('late@example.com');
    const user = await findUserByEmail(pool, 'late@example.com');
    await pool.query(
      'UPDATE auth_codes SET expires_at = DATE_SUB(NOW(), INTERVAL 1 MINUTE) WHERE user_id = ?',
      [user.user_id],
    );
    assert.equal((await verify('late@example.com', good)).status, 400);
  });

  await t.test('the old link route is gone', async () => {
    const res = await request(app).get('/api/v1/auth/verify-email?token=abc');
    assert.equal(res.status, 404);
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

  await t.test('a correct resend on a still-unverified account sends a new code that replaces the old', async () => {
    await register('resend@example.com', 'correct horse battery');
    const first = lastCode('resend@example.com');
    await ageCode('resend@example.com');
    const before = mail.sent.length;

    const good = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'resend@example.com', password: 'correct horse battery' });
    const bad = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'resend@example.com', password: 'wrong' });
    assert.equal(good.status, 202);
    assert.equal(bad.status, 202);
    assert.equal(good.text, bad.text);

    const resent = mail.sent.slice(before);
    assert.equal(resent.length, 1, 'only the correct-credential call sent anything');
    const second = codeIn(resent[0]);
    if (second !== first) {
      assert.equal((await verify('resend@example.com', first)).status, 400,
        'only the latest code works');
    }
    assert.equal((await verify('resend@example.com', second)).status, 200);
  });

  await t.test('a resend within a minute answers the same but sends nothing', async () => {
    await register('quick@example.com', 'correct horse battery');
    const before = mail.sent.length;
    const res = await request(app).post('/api/v1/auth/verify-email/request')
      .send({ email: 'quick@example.com', password: 'correct horse battery' });
    assert.equal(res.status, 202);
    assert.equal(mail.sent.length, before, 'the one-per-minute limit held it back');
  });

  await t.test('an unparseable email is refused outright', async () => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'notanemail', password: 'correct horse', fullName: 'X' });
    assert.equal(res.status, 400);
  });

  await t.test('registration survives a mail outage', async () => {
    const failingMail = { send: async () => { throw new Error('smtp is down'); } };
    const failingApp = buildTestApp({ pool, mail: failingMail });

    const res = await request(failingApp).post('/api/v1/auth/register').send({
      email: 'outage@example.com', password: 'correct horse', fullName: 'Outage',
    });
    assert.equal(res.status, 201, 'a mail outage must not fail registration');

    const user = await findUserByEmail(pool, 'outage@example.com');
    assert.ok(user, 'the user row must still be created');
    const [codes] = await pool.query(
      "SELECT * FROM auth_codes WHERE user_id = ? AND purpose = 'verify_email'",
      [user.user_id],
    );
    assert.equal(codes.length, 1, 'the code is issued, so a resend can follow');
  });
});
