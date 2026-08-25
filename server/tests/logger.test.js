'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const pino = require('pino');
const { Writable } = require('node:stream');

test('redacts sensitive fields at multiple nesting levels', () => {
  let capturedOutput = '';

  const destination = new Writable({
    write(chunk, encoding, callback) {
      capturedOutput += chunk.toString();
      callback();
    },
  });

  // Create logger with redaction paths, using production env to avoid pino-pretty
  const logger = pino({
    level: 'info',
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'password',
        '*.password',
        '*.*.password',
        'req.body.password',
        'password_hash',
        '*.password_hash',
        '*.*.password_hash',
        'req.body.password_hash',
        'token',
        '*.token',
        '*.*.token',
        'req.body.token',
      ],
      censor: '[REDACTED]',
    },
  }, destination);

  logger.info({
    password: 'secret123',
    user: { password: 'level1' },
    req: { body: { password: 'level2' } },
    email: 'test@example.com',
  });

  const logged = JSON.parse(capturedOutput);

  // Top-level password is redacted
  assert.equal(logged.password, '[REDACTED]', 'top-level password should be redacted');

  // One-level nested password is redacted
  assert.equal(logged.user.password, '[REDACTED]', 'user.password should be redacted');

  // Two-level nested password (in req.body) is redacted
  assert.equal(logged.req.body.password, '[REDACTED]', 'req.body.password should be redacted');

  // Non-sensitive fields pass through unchanged
  assert.equal(logged.email, 'test@example.com', 'non-sensitive fields should pass through');
});
