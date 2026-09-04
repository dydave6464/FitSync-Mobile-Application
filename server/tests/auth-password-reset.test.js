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

  await t.test('the response is identical for every kind of address', async () => {
    await request(app).post('/api/v1/auth/register').send({
      email: 'known@example.com', password: 'correct horse', fullName: 'K',
    });
    const unknown = await ask('nobody@example.com');
    const unverified = await ask('known@example.com');

    assert.equal(unknown.status, 202);
    assert.equal(unverified.status, 202);
    assert.deepEqual(unknown.body, unverified.body,
      'any difference here makes this an account-enumeration oracle');
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
  });
});
