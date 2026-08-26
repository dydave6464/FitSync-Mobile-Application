'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Writable } = require('node:stream');
const express = require('express');
const request = require('supertest');
const { createApp } = require('../src/app');
const { createLogger } = require('../src/lib/logger');

function captureLogger() {
  let output = '';
  const destination = new Writable({
    write(chunk, _encoding, callback) {
      output += chunk.toString();
      callback();
    },
  });
  // production env avoids the pino-pretty transport, which runs on a worker
  // thread and would bypass our synchronous capture stream.
  const logger = createLogger({ level: 'info', env: 'production', destination });
  return { logger, lines: () => output.split('\n').filter(Boolean).map((l) => JSON.parse(l)) };
}

function buildLoggedApp(logger) {
  const probe = express.Router();
  probe.post('/probe', (req, res) => res.json({ data: { ok: true } }));
  probe.get('/probe', (req, res) => res.json({ data: { ok: true } }));
  return createApp({ config: { env: 'test' }, logger, pool: null, extraRouter: probe });
}

test('every request is logged with correlation id, method, url, status and duration', async () => {
  const { logger, lines } = captureLogger();
  const app = buildLoggedApp(logger);

  const res = await request(app).get('/api/v1/probe');
  assert.equal(res.status, 200);

  const requestLine = lines().find((l) => l.req && l.req.url === '/api/v1/probe');
  assert.ok(requestLine, 'expected a log line for the request');
  assert.equal(requestLine.req.id, res.headers['x-request-id']);
  assert.equal(requestLine.req.method, 'GET');
  assert.equal(requestLine.res.statusCode, 200);
  assert.equal(typeof requestLine.responseTime, 'number');
});

test('a password in the JSON request body never reaches the log output', async () => {
  const { logger, lines } = captureLogger();
  const app = buildLoggedApp(logger);

  await request(app).post('/api/v1/probe').send({ password: 'SHOULD_NOT_APPEAR' });

  const raw = JSON.stringify(lines());
  assert.doesNotMatch(raw, /SHOULD_NOT_APPEAR/);
});

test('an Authorization header is redacted rather than logged in the clear', async () => {
  const { logger, lines } = captureLogger();
  const app = buildLoggedApp(logger);

  await request(app).get('/api/v1/probe').set('Authorization', 'Bearer super-secret-token');

  const raw = JSON.stringify(lines());
  assert.doesNotMatch(raw, /super-secret-token/);

  const requestLine = lines().find((l) => l.req && l.req.url === '/api/v1/probe' && l.req.headers);
  assert.equal(requestLine.req.headers.authorization, '[REDACTED]');
});
