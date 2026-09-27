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
  for (const bad of ['FitSync', 'FitSync <not-an-address>', 'hello@fitsync', 'a@b@c.com']) {
    assert.throws(() => brevo.create({ apiKey: KEY, from: bad }), /MAIL_FROM/, bad);
  }
});

test('MAIL_FROM tolerates spaces inside the brackets and quoted names', () => {
  assert.deepEqual(brevo.parseFrom('FitSync < hello@fitsync.test >'),
    { name: 'FitSync', email: 'hello@fitsync.test' });
  assert.deepEqual(brevo.parseFrom('"FitSync, Team" <hello@fitsync.test>'),
    { name: 'FitSync, Team', email: 'hello@fitsync.test' });
  assert.deepEqual(brevo.parseFrom("'FitSync' <hello@fitsync.test>"),
    { name: 'FitSync', email: 'hello@fitsync.test' });
});

test('a key that cannot travel in a header is refused at startup, without echoing it', () => {
  for (const bad of ['xkeysib-abc\ndef', 'xkeysib-abc def', 'xkeysib-abc\u0000def']) {
    assert.throws(() => brevo.create({ apiKey: bad, from: 'hello@fitsync.test' }), (err) => {
      assert.match(err.message, /BREVO_API_KEY/);
      assert.ok(!err.message.includes('abc'), 'the key must not appear in the error');
      return true;
    });
  }
});

test('a long or odd Brevo reason is kept short and readable', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 400, json: async () => ({ message: 'x'.repeat(500) }) }),
    async () => {
      const mail = brevo.create({ apiKey: KEY, from: 'hello@fitsync.test' });
      await assert.rejects(() => mail.send({ to: 'a@b.c', subject: 's', text: 't' }), (err) => {
        assert.ok(err.message.length < 260, `message is ${err.message.length} long`);
        return true;
      });
    },
  ).then(() => withFakeFetch(
    async () => ({ ok: false, status: 400, json: async () => ({ message: { nested: true } }) }),
    async () => {
      const mail = brevo.create({ apiKey: KEY, from: 'hello@fitsync.test' });
      await assert.rejects(
        () => mail.send({ to: 'a@b.c', subject: 's', text: 't' }),
        (err) => !/object Object/.test(err.message) && /400/.test(err.message),
      );
    },
  )));

test('a successful response body is released, not left holding the connection', () => {
  let cancelled = false;
  return withFakeFetch(
    async () => ({
      ok: true,
      status: 201,
      body: { cancel: async () => { cancelled = true; } },
    }),
    async () => {
      await brevo.create({ apiKey: KEY, from: 'hello@fitsync.test' })
        .send({ to: 'a@b.c', subject: 's', text: 't' });
      assert.ok(cancelled);
    },
  );
});

test('the key never reaches the error, its causes, or the log line', () =>
  withFakeFetch(
    async () => {
      throw new TypeError('fetch failed', { cause: new Error('connect ECONNREFUSED') });
    },
    async () => {
      const { createLogger } = require('../src/lib/logger');
      const { Writable } = require('node:stream');
      let logged = '';
      const sink = new Writable({ write(chunk, _enc, done) { logged += chunk; done(); } });
      const logger = createLogger({ level: 'error', env: 'test', destination: sink });
      const mail = brevo.create({ apiKey: KEY, from: 'hello@fitsync.test' });
      const err = await mail.send({ to: 'a@b.c', subject: 's', text: 't' }).catch((e) => e);
      logger.error({ err }, 'verification email failed to send');
      await new Promise((r) => setImmediate(r));
      for (let e = err; e; e = e.cause) {
        assert.ok(!String(e.message).includes(KEY), 'a cause carries the key');
      }
      assert.ok(logged.length > 0, 'the log line was written');
      assert.ok(!logged.includes(KEY), 'the log line carries the key');
    },
  ));
