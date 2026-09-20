'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Writable } = require('node:stream');
const express = require('express');
const request = require('supertest');
const { createApp, reqSerializer } = require('../src/app');
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

// A pool that answers readSharedReport with one live report row, so the real
// GET /reports/:token handler renders a real page without a database.
function reportPool() {
  return {
    query: async () => [[{
      user_id: 7,
      period: 'week',
      window_start: new Date('2026-09-12T00:00:00Z'),
      window_end: new Date('2026-09-19T00:00:00Z'),
      report_json: JSON.stringify({
        summary: { sessionCount: 3, setCount: 12, totalVolumeKg: 4800 },
      }),
      expires_at_epoch: Math.floor(Date.now() / 1000) + 86400,
      full_name: 'Juan Dela Cruz',
    }]],
  };
}

function buildLoggedApp(logger, pool = null) {
  const probe = express.Router();
  probe.post('/probe', (req, res) => res.json({ data: { ok: true } }));
  probe.get('/probe', (req, res) => res.json({ data: { ok: true } }));
  return createApp({ config: { env: 'test' }, logger, pool, extraRouter: probe });
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

test('a token in the request URL never reaches the log output', async () => {
  // Both the emailed verify-email and password-reset links carry the raw
  // token as a query string parameter. pino-http's default req serializer
  // logs req.url from req.originalUrl, which includes the query string as
  // one literal string -- so the path-based redact rules on req.query.token
  // do not reach it; the value shows up unredacted right next to it.
  const { logger, lines } = captureLogger();
  const app = buildLoggedApp(logger);

  await request(app).get('/api/v1/probe?token=RAWTOKENVALUESHOULDNOTAPPEAR12345');

  const raw = JSON.stringify(lines());
  assert.doesNotMatch(raw, /RAWTOKENVALUESHOULDNOTAPPEAR12345/);

  const requestLine = lines().find((l) => l.req && l.req.method === 'GET' && l.req.url);
  assert.ok(requestLine, 'expected a log line for the request');
  assert.equal(requestLine.req.url, '/api/v1/probe', 'the path is still worth keeping in the log');
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

// The share-a-report token is the one credential that rides in the PATH, not
// the query string, so the '?'-stripping above misses it entirely. It is also
// the longest-lived of the three: 30 days of access to a named person's
// training data, handed to whoever holds it.
//
// Tested on the serializer directly rather than only through the app because
// tests/helpers/test-app.js builds every other suite's app with a 'silent'
// logger -- the log line this guards is structurally invisible to all of them,
// so a regression here would have nothing to fail against.
test('a share token in the request PATH is redacted by the serializer', () => {
  const token = 'A'.repeat(43);
  const serialized = reqSerializer({
    method: 'GET',
    url: `/api/v1/reports/${token}`,
    headers: {},
    socket: {},
  });

  assert.equal(serialized.url, '/api/v1/reports/[REDACTED]');
  assert.doesNotMatch(JSON.stringify(serialized), new RegExp(token));
});

test('an ordinary url survives the share-token redaction untouched', () => {
  const urls = [
    '/api/v1/sessions/history',
    '/api/v1/reports',
    '/api/v1/auth/login',
  ];

  for (const url of urls) {
    const serialized = reqSerializer({ method: 'GET', url, headers: {}, socket: {} });
    assert.equal(serialized.url, url);
  }
});

// And the same property end to end, so the serializer is proven to be the one
// pino-http actually runs. A stub pool that answers "no such row" reaches the
// real GET /reports/:token handler and its 404 page without a database.
test('a share token never reaches the log output through the real route', async () => {
  const { logger, lines } = captureLogger();
  const noRows = { query: async () => [[undefined]] };
  const app = buildLoggedApp(logger, noRows);
  const token = 'Z'.repeat(43);

  await request(app).get(`/api/v1/reports/${token}`).expect(404);

  const raw = JSON.stringify(lines());
  assert.doesNotMatch(raw, new RegExp(token));

  const requestLine = lines().find((l) => l.req && l.req.url && l.req.url.startsWith('/api/v1/reports/'));
  assert.ok(requestLine, 'expected a log line for the request');
  assert.equal(requestLine.req.url, '/api/v1/reports/[REDACTED]');
});

// Express leaves `case sensitive routing` DISABLED by default and this app
// never enables it, so the path this redaction has to cover is not only the
// lowercase one. An anchored lowercase pattern misses exactly the request
// that succeeded.
test('a share token is redacted whatever case the path was written in', () => {
  const token = 'C'.repeat(43);
  const variants = [
    `/API/V1/REPORTS/${token}`,
    `/API/V1/Reports/${token}`,
    `/Api/v1/rEpOrTs/${token}`,
  ];

  for (const url of variants) {
    const serialized = reqSerializer({ method: 'GET', url, headers: {}, socket: {} });
    assert.doesNotMatch(serialized.url, new RegExp(token), `${url} leaked its token`);
    // The prefix survives exactly as written, so the log still shows which
    // route shape the request actually took. Only the token segment is gone.
    assert.equal(serialized.url, `${url.slice(0, url.lastIndexOf('/') + 1)}[REDACTED]`);
  }
});

// The case variant is not hypothetical: it reaches the real handler and
// serves the report, so the line it writes is the log line of a SUCCESSFUL
// view of a named person's training data. Asserting the 200 and the rendered
// name is the point -- a 404 here would make the redaction untested.
test('a case-variant report URL serves the report and still logs no token', async () => {
  const { logger, lines } = captureLogger();
  const token = 'V'.repeat(43);
  const app = buildLoggedApp(logger, reportPool());

  const res = await request(app).get(`/API/V1/Reports/${token}`).expect(200);
  assert.match(res.headers['content-type'], /text\/html/);
  assert.match(res.text, /Training report/, 'the case variant reaches the report handler');
  assert.match(res.text, /Juan Dela Cruz/, 'and renders the real report, not an error page');

  assert.doesNotMatch(JSON.stringify(lines()), new RegExp(token));

  const requestLine = lines().find((l) => l.req && l.req.url && /reports/i.test(l.req.url));
  assert.ok(requestLine, 'expected a log line for the request');
  assert.equal(requestLine.req.url, '/API/V1/Reports/[REDACTED]');
});

// A share link pasted with one stray trailing character misses the route and
// falls through to notFound, which interpolates originalUrl into a message
// error-handler.js logs at warn. Same 30-day credential, a different writer
// from the request logger above.
test('a share token in an unmatched URL never reaches the log output', async () => {
  const { logger, lines } = captureLogger();
  const token = 'N'.repeat(43);
  const app = buildLoggedApp(logger);

  await request(app).get(`/api/v1/reports/${token}/x`).expect(404);

  assert.doesNotMatch(JSON.stringify(lines()), new RegExp(token));

  const warnLine = lines().find((l) => l.msg && l.msg.startsWith('No route matches'));
  assert.ok(warnLine, 'expected the 404 warning line');
  assert.equal(warnLine.msg, 'No route matches GET /api/v1/reports/[REDACTED]/x');
});
