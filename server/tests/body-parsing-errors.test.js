'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { buildTestApp } = require('./helpers/test-app');

test('malformed JSON returns 400 INVALID_REQUEST_BODY with a correlation id', async () => {
  const res = await request(buildTestApp())
    .post('/api/v1/does-not-exist')
    .set('Content-Type', 'application/json')
    .send('{not valid json');

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'INVALID_REQUEST_BODY');
  assert.match(res.headers['x-request-id'], /^[0-9a-f-]{36}$/);
});

test('an oversized body returns 413 PAYLOAD_TOO_LARGE with a correlation id', async () => {
  const oversized = 'x'.repeat(2 * 1024 * 1024);
  const res = await request(buildTestApp())
    .post('/api/v1/does-not-exist')
    .set('Content-Type', 'application/json')
    .send(JSON.stringify({ big: oversized }));

  assert.equal(res.status, 413);
  assert.equal(res.body.error.code, 'PAYLOAD_TOO_LARGE');
  assert.match(res.headers['x-request-id'], /^[0-9a-f-]{36}$/);
});

test('a body-parser error never echoes the raw parser message to the client', async () => {
  const res = await request(buildTestApp())
    .post('/api/v1/does-not-exist')
    .set('Content-Type', 'application/json')
    .send('{not valid json');

  assert.equal(res.status, 400);
  assert.doesNotMatch(JSON.stringify(res.body), /not valid json/);
});
