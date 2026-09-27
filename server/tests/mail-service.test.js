'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createMailService } = require('../src/services/mail');
const { load } = require('../src/config');

const baseEnv = {
  DB_HOST: 'h', DB_PORT: '3306', DB_USER: 'u', DB_PASSWORD: 'p',
  DB_NAME: 'd', JWT_SECRET: 's',
};

test('the stub records what it would have sent', async () => {
  const mail = createMailService({ mode: 'stub' });
  await mail.send({ to: 'a@b.c', subject: 'Verify', text: 'link: http://x/y' });
  assert.equal(mail.sent.length, 1);
  assert.equal(mail.sent[0].to, 'a@b.c');
  assert.match(mail.sent[0].text, /http:\/\/x\/y/);
});

test('smtp mode refuses to start without credentials', () => {
  assert.throws(() => createMailService({ mode: 'smtp' }), /SMTP_HOST/);
});

test('brevo mode refuses to start without its key or sender', () => {
  assert.throws(() => createMailService({ mode: 'brevo' }), /BREVO_API_KEY/);
  assert.throws(() => createMailService({ mode: 'brevo' }), /MAIL_FROM/);
  assert.throws(
    () => createMailService({ mode: 'brevo', brevo: { apiKey: 'k' } }),
    (err) => /MAIL_FROM/.test(err.message) && !/BREVO_API_KEY/.test(err.message),
  );
});

test('brevo mode builds a sender when both are set', () => {
  const mail = createMailService({
    mode: 'brevo', brevo: { apiKey: 'k', from: 'FitSync <hello@fitsync.test>' },
  });
  assert.equal(typeof mail.send, 'function');
});

test('the config reads BREVO_API_KEY and MAIL_FROM for brevo mode', () => {
  const config = load({
    ...baseEnv, MAIL_MODE: 'brevo', BREVO_API_KEY: 'xkeysib-1', MAIL_FROM: 'a@b.c',
  });
  assert.equal(config.mail.mode, 'brevo');
  assert.deepEqual(config.mail.brevo, { apiKey: 'xkeysib-1', from: 'a@b.c' });
});

test('brevo mail in production is allowed', () => {
  const config = load({
    ...baseEnv, NODE_ENV: 'production', GOOGLE_MODE: 'http', GOOGLE_CLIENT_ID: 'x',
    MAIL_MODE: 'brevo', BREVO_API_KEY: 'k', MAIL_FROM: 'a@b.c',
    PUBLIC_BASE_URL: 'https://api.fitsync.test',
  });
  assert.equal(config.mail.mode, 'brevo');
});

test('an unknown mode is refused', () => {
  assert.throws(() => createMailService({ mode: 'carrier-pigeon' }), /carrier-pigeon/);
});

test('stub mail in production refuses to boot', () => {
  // Verification is a hard gate, so stub mail in production does not degrade
  // -- it means nobody can register at all. Fail at startup, not in an incident.
  assert.throws(
    () => load({ ...baseEnv, NODE_ENV: 'production', GOOGLE_MODE: 'http',
                 GOOGLE_CLIENT_ID: 'x', MAIL_MODE: 'stub' }),
    /MAIL_MODE=smtp or MAIL_MODE=brevo/,
  );
});

test('stub mail outside production is fine', () => {
  const config = load({ ...baseEnv, MAIL_MODE: 'stub' });
  assert.equal(config.mail.mode, 'stub');
});

test('publicBaseUrl has a development default', () => {
  const config = load({ ...baseEnv });
  assert.equal(config.publicBaseUrl, 'http://localhost:3000');
});
