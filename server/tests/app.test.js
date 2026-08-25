'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { buildTestApp } = require('./helpers/test-app');
const AppError = require('../src/lib/app-error');

test('unmatched route returns the error envelope, not Express HTML', async () => {
  const res = await request(buildTestApp()).get('/api/v1/does-not-exist');
  assert.equal(res.status, 404);
  assert.equal(res.body.error.code, 'NOT_FOUND');
  assert.ok(Array.isArray(res.body.error.details));
  assert.equal(res.body.data, undefined);
});

test('an AppError renders with its own status and code', async () => {
  const app = buildTestApp({
    extend: (router) => {
      router.get('/boom', () => {
        throw AppError.conflict('ALREADY_EXISTS', 'That already exists');
      });
    },
  });
  const res = await request(app).get('/api/v1/boom');
  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, 'ALREADY_EXISTS');
  assert.equal(res.body.error.message, 'That already exists');
});

test('an unexpected throw becomes 500 without leaking the stack', async () => {
  const app = buildTestApp({
    extend: (router) => {
      router.get('/kaboom', () => {
        throw new Error('database password is hunter2');
      });
    },
  });
  const res = await request(app).get('/api/v1/kaboom');
  assert.equal(res.status, 500);
  assert.equal(res.body.error.code, 'INTERNAL_ERROR');
  assert.doesNotMatch(JSON.stringify(res.body), /hunter2/);
  assert.doesNotMatch(JSON.stringify(res.body), /at .*app\.js/);
});

test('every response carries a correlation id', async () => {
  const res = await request(buildTestApp()).get('/api/v1/nope');
  assert.match(res.headers['x-request-id'], /^[0-9a-f-]{36}$/);
});

test('an inbound X-Request-Id is preserved', async () => {
  const res = await request(buildTestApp())
    .get('/api/v1/nope')
    .set('X-Request-Id', 'client-supplied-id');
  assert.equal(res.headers['x-request-id'], 'client-supplied-id');
});
