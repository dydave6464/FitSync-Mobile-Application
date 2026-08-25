'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Writable } = require('node:stream');
const { createLogger } = require('../src/lib/logger');

test('redacts sensitive fields at multiple nesting levels', () => {
  let capturedOutput = '';

  const destination = new Writable({
    write(chunk, encoding, callback) {
      capturedOutput += chunk.toString();
      callback();
    },
  });

  // Create logger via createLogger, using production env to avoid pino-pretty
  const logger = createLogger({ level: 'info', env: 'production', destination });

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
