'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const brevo = require('../src/services/mail/brevo');

const KEY = 'xkeysib-test-key-never-logged';

/// Replaces fetch for one test; `impl` sees exactly what would go to Brevo.
function withFakeFetch(impl, fn) {
  const original = global.fetch;
  global.fetch = impl;
  return fn().finally(() => {
    global.fetch = original;
  });
}

const created = () => ({ ok: true, status: 201, json: async () => ({ messageId: '<1@smtp-relay>' }) });

test('sends one POST to Brevo\'s transactional email API', () => {
  let call;
  return withFakeFetch(
    async (url, options) => {
      call = { url: String(url), options };
      return created();
    },
    async () => {
      const mail = brevo.create({ apiKey: KEY, from: 'FitSync <hello@fitsync.test>' });
      await mail.send({ to: 'juan@example.com', subject: 'Verify', text: 'Tap: http://x/y' });

      assert.equal(call.url, 'https://api.brevo.com/v3/smtp/email');
      assert.equal(call.options.method, 'POST');
      assert.equal(call.options.headers['api-key'], KEY);
      assert.equal(call.options.headers['content-type'], 'application/json');
      assert.ok(call.options.signal instanceof AbortSignal, 'a timeout is attached');
      assert.deepEqual(JSON.parse(call.options.body), {
        sender: { name: 'FitSync', email: 'hello@fitsync.test' },
        to: [{ email: 'juan@example.com' }],
        subject: 'Verify',
        textContent: 'Tap: http://x/y',
      });
    },
  );
});

test('a bare MAIL_FROM address is sent without a display name', () => {
  let body;
  return withFakeFetch(
    async (_url, options) => {
      body = JSON.parse(options.body);
      return created();
    },
    async () => {
      await brevo.create({ apiKey: KEY, from: 'hello@fitsync.test' })
        .send({ to: 'a@b.c', subject: 's', text: 't' });
      assert.deepEqual(body.sender, { email: 'hello@fitsync.test' });
    },
  );
});

test('a refusal names the status and Brevo\'s reason, never the key', () =>
  withFakeFetch(
    async () => ({
      ok: false,
      status: 401,
      json: async () => ({ code: 'unauthorized', message: 'Key not found' }),
    }),
    async () => {
      const mail = brevo.create({ apiKey: KEY, from: 'hello@fitsync.test' });
      await assert.rejects(() => mail.send({ to: 'a@b.c', subject: 's', text: 't' }), (err) => {
        assert.match(err.message, /401/);
        assert.match(err.message, /Key not found/);
        assert.ok(!err.message.includes(KEY), 'the key must not appear in the error');
        return true;
      });
    },
  ));

test('a refusal with an unreadable body still names the status', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 503, json: async () => { throw new SyntaxError('x'); } }),
    async () => {
      const mail = brevo.create({ apiKey: KEY, from: 'hello@fitsync.test' });
      await assert.rejects(() => mail.send({ to: 'a@b.c', subject: 's', text: 't' }), /503/);
    },
  ));

test('a network failure or timeout is wrapped, never showing the key', () =>
  withFakeFetch(
    async () => {
      throw new DOMException('The operation was aborted due to timeout', 'TimeoutError');
    },
    async () => {
      const mail = brevo.create({ apiKey: KEY, from: 'hello@fitsync.test' });
      await assert.rejects(() => mail.send({ to: 'a@b.c', subject: 's', text: 't' }), (err) => {
        assert.match(err.message, /Brevo/);
        assert.match(err.message, /timeout/i);
        assert.ok(!err.message.includes(KEY));
        return true;
      });
    },
  ));

test('an unusable MAIL_FROM is refused when the service is built', () => {
  assert.throws(() => brevo.create({ apiKey: KEY, from: 'FitSync' }), /MAIL_FROM/);
  assert.throws(() => brevo.create({ apiKey: KEY, from: 'FitSync <not-an-address>' }), /MAIL_FROM/);
});
