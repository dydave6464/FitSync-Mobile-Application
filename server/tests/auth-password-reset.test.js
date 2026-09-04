'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createMailService } = require('../src/services/mail');

test('password reset', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const mail = createMailService({ mode: 'stub' });
  const app = buildTestApp({ pool, mail });

  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const ask = (email) =>
    request(app).post('/api/v1/auth/password-reset/request').send({ email });

  await t.test('the response is identical for every kind of address, including verified', async () => {
    await request(app).post('/api/v1/auth/register').send({
      email: 'known@example.com', password: 'correct horse', fullName: 'K',
    });
    await request(app).post('/api/v1/auth/register').send({
      email: 'verified@example.com', password: 'correct horse', fullName: 'V',
    });
    const verifyLink = mail.sent.find((m) => /verify-email/.test(m.text) && m.to === 'verified@example.com');
    const verifyToken = verifyLink.text.match(/token=([a-f0-9]{64})/)[1];
    await request(app).get(`/api/v1/auth/verify-email?token=${verifyToken}`);

    const unknown = await ask('nobody@example.com');
    const unverified = await ask('known@example.com');
    // The verified branch is the only one of the three that actually does
    // something different -- it issues a token and sends mail -- so it is
    // the only branch that can actually reveal a difference. Comparing just
    // unknown vs. unverified (as this test used to) would still pass even if
    // the verified branch returned a different status entirely.
    const verified = await ask('verified@example.com');

    assert.equal(unknown.status, 202);
    assert.equal(unverified.status, 202);
    assert.equal(verified.status, 202);
    // Byte-identical, not just deepEqual on the parsed body: the spec asks
    // for responses an observer cannot tell apart, and comparing raw text
    // also catches a difference in headers/whitespace that JSON parsing
    // would silently normalize away.
    assert.equal(unknown.text, unverified.text,
      'any difference here makes this an account-enumeration oracle');
    assert.equal(unverified.text, verified.text,
      'the verified branch actually sends mail, but must still look identical');
  });

  await t.test('an unverified account is sent no reset link', async () => {
    const before = mail.sent.length;
    await ask('known@example.com');
    const resets = mail.sent.slice(before).filter((m) => /password-reset/.test(m.text));
    assert.equal(resets.length, 0,
      'mailing a reset to an unproven address is a takeover path, not recovery');
  });

  await t.test('a verified account can reset and sign in with the new password', async () => {
    const verify = mail.sent.find((m) => /verify-email/.test(m.text));
    const vToken = verify.text.match(/token=([a-f0-9]{64})/)[1];
    await request(app).get(`/api/v1/auth/verify-email?token=${vToken}`);

    const before = mail.sent.length;
    await ask('known@example.com');
    const reset = mail.sent.slice(before).find((m) => /password-reset/.test(m.text));
    assert.ok(reset, 'a verified account does get a link');
    const token = reset.text.match(/token=([a-f0-9]{64})/)[1];

    const form = await request(app).get(`/api/v1/auth/password-reset?token=${token}`);
    assert.equal(form.status, 200);
    assert.match(form.headers['content-type'], /html/);
    assert.equal(form.headers['cache-control'], 'no-store',
      'this page embeds a live reset token in a hidden field and must never be cached');

    const done = await request(app).post('/api/v1/auth/password-reset')
      .type('form').send({ token, password: 'a whole new password' });
    assert.equal(done.status, 200);

    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'known@example.com', password: 'a whole new password' });
    assert.equal(login.status, 200);
  });

  await t.test('opening the form does not spend the token', async () => {
    // Otherwise merely clicking the link, or a mail client prefetching it,
    // would burn the reset before the user typed anything.
    const before = mail.sent.length;
    await ask('known@example.com');
    const token = mail.sent.slice(before)
      .find((m) => /password-reset/.test(m.text)).text.match(/token=([a-f0-9]{64})/)[1];

    await request(app).get(`/api/v1/auth/password-reset?token=${token}`);
    const done = await request(app).post('/api/v1/auth/password-reset')
      .type('form').send({ token, password: 'still works fine' });
    assert.equal(done.status, 200);
  });

  await t.test('a verification token cannot be spent as a reset', async () => {
    const verify = mail.sent.find((m) => /verify-email/.test(m.text));
    const vToken = verify.text.match(/token=([a-f0-9]{64})/)[1];
    const res = await request(app).post('/api/v1/auth/password-reset')
      .type('form').send({ token: vToken, password: 'should not work' });
    assert.equal(res.status, 400);
    // This route is opened straight from an emailed link -- a rejected
    // (here: wrong-purpose) token must fail into a page, not the JSON error
    // envelope the JSON API uses everywhere else.
    assert.match(res.headers['content-type'], /html/,
      'a browser-facing route must fail into a page, not a JSON error object');
  });

  await t.test('a too-short password does not spend the token', async () => {
    // consumeToken marks the row spent unconditionally, so a rejected
    // password must be validated BEFORE the token is consumed -- otherwise a
    // simple mistake burns the one-time link and forces a whole new email.
    const before = mail.sent.length;
    await ask('known@example.com');
    const token = mail.sent.slice(before)
      .find((m) => /password-reset/.test(m.text)).text.match(/token=([a-f0-9]{64})/)[1];

    const tooShort = await request(app).post('/api/v1/auth/password-reset')
      .type('form').send({ token, password: 'short' });
    assert.equal(tooShort.status, 400,
      'a rejected password must not look like a successful reset');
    assert.match(tooShort.headers['content-type'], /html/,
      'the retry must be a page the user can act on, not a JSON error object');
    assert.match(tooShort.text, new RegExp(`value="${token}"`),
      'the token must survive into the retry form so the user does not have to reopen the email');
    assert.equal(tooShort.headers['cache-control'], 'no-store',
      'this page embeds a live reset token and must never be cached');

    const retry = await request(app).post('/api/v1/auth/password-reset')
      .type('form').send({ token, password: 'a good password this time' });
    assert.equal(retry.status, 200,
      'the same token must still work -- the failed attempt must not have spent it');
  });
});
