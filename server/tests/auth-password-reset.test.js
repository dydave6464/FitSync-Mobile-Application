'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createMailService } = require('../src/services/mail');

const codeIn = (message) => message.subject.match(/(\d{6})$/)[1];

test('password reset', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const mail = createMailService({ mode: 'stub' });
  const app = buildTestApp({ pool, mail });

  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const ask = (email) =>
    request(app).post('/api/v1/auth/password-reset/request').send({ email });
  const reset = (body) => request(app).post('/api/v1/auth/password-reset').send(body);
  const mailsTo = (email, pattern) =>
    mail.sent.filter((m) => m.to === email && pattern.test(m.subject));
  const registerVerified = async (email, password = 'correct horse') => {
    await request(app).post('/api/v1/auth/register').send({ email, password, fullName: 'R' });
    const [m] = mailsTo(email, /^Your FitSync code:/);
    await request(app).post('/api/v1/auth/verify-email').send({ email, code: codeIn(m) });
  };
  const resetCode = (email) => codeIn(mailsTo(email, /password reset code/).at(-1));
  const other = (code) => (code === '000000' ? '111111' : '000000');
  const login = (email, password) =>
    request(app).post('/api/v1/auth/login').send({ email, password });

  await t.test('the response is identical for every kind of address, including verified', async () => {
    await request(app).post('/api/v1/auth/register').send({
      email: 'unverified@example.com', password: 'correct horse', fullName: 'U',
    });
    await registerVerified('verified@example.com');

    const unknown = await ask('nobody@example.com');
    const unverified = await ask('unverified@example.com');
    const verified = await ask('verified@example.com');
    for (const r of [unknown, unverified, verified]) assert.equal(r.status, 202);
    assert.equal(unknown.text, unverified.text);
    assert.equal(unverified.text, verified.text,
      'the verified branch actually sends mail, but must still look identical');
  });

  await t.test('an unverified account is sent no reset code', async () => {
    assert.equal(mailsTo('unverified@example.com', /password reset code/).length, 0,
      'mailing a reset to an unproven address is a takeover path, not recovery');
  });

  await t.test('the reset email carries a code and no link', async () => {
    const [m] = mailsTo('verified@example.com', /password reset code/);
    assert.match(m.subject, /^Your FitSync password reset code: \d{6}$/);
    assert.ok(m.text.includes(codeIn(m)));
    assert.doesNotMatch(m.text, /https?:\/\//);
    assert.match(m.text, /15 minutes/);
  });

  await t.test('a too-short password is refused without spending an attempt', async () => {
    const code = resetCode('verified@example.com');
    for (let i = 0; i < 6; i += 1) {
      const res = await reset({ email: 'verified@example.com', code, password: 'short' });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
    }
    // Six refusals, more than the five-attempt limit: the code must still work.
    const done = await reset({
      email: 'verified@example.com', code, password: 'a whole new password',
    });
    assert.equal(done.status, 200);
    assert.deepEqual(done.body, { data: { reset: true } });
  });

  await t.test('the new password signs in and the old one does not', async () => {
    assert.equal((await login('verified@example.com', 'a whole new password')).status, 200);
    assert.equal((await login('verified@example.com', 'correct horse')).status, 401);
  });

  await t.test('a used code is CODE_INVALID', async () => {
    const res = await reset({
      email: 'verified@example.com', code: resetCode('verified@example.com'),
      password: 'yet another password',
    });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'CODE_INVALID');
  });

  await t.test('every wrong answer looks exactly the same', async () => {
    await registerVerified('second@example.com');
    await ask('second@example.com');
    const good = resetCode('second@example.com');
    const body = (email, code) => ({ email, code, password: 'a fine new password' });
    const responses = [
      await reset(body('second@example.com', other(good))),
      await reset(body('nobody@example.com', good)),
      await reset(body('unverified@example.com', good)),
      await reset(body('second@example.com', '12345')),
      await reset(body('second@example.com', undefined)),
    ];
    for (const r of responses) {
      assert.equal(r.status, 400);
      assert.equal(r.body.error.code, 'CODE_INVALID');
    }
    assert.equal(new Set(responses.map((r) => r.text)).size, 1);
  });

  await t.test('a second request within a minute sends nothing', async () => {
    const before = mailsTo('second@example.com', /password reset code/).length;
    await ask('second@example.com');
    assert.equal(mailsTo('second@example.com', /password reset code/).length, before);
  });

  await t.test('the old link form is gone', async () => {
    assert.equal((await request(app).get('/api/v1/auth/password-reset?token=abc')).status, 404);
  });
});
