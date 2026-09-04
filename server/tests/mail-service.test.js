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

test('an unknown mode is refused', () => {
  assert.throws(() => createMailService({ mode: 'carrier-pigeon' }), /carrier-pigeon/);
});

test('stub mail in production refuses to boot', () => {
  // Verification is a hard gate, so stub mail in production does not degrade
  // -- it means nobody can register at all. Fail at startup, not in an incident.
  assert.throws(
    () => load({ ...baseEnv, NODE_ENV: 'production', GOOGLE_MODE: 'http',
                 GOOGLE_CLIENT_ID: 'x', MAIL_MODE: 'stub' }),
    /MAIL_MODE/,
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
