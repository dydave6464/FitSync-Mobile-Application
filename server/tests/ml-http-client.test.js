'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const httpClient = require('../src/services/ml/http-client');

function withFakeFetch(impl, fn) {
  const original = global.fetch;
  global.fetch = impl;
  return fn().finally(() => {
    global.fetch = original;
  });
}

test('generatePlan attaches a request timeout so a hung ML service cannot hang forever', () =>
  withFakeFetch(
    async (_url, options) => {
      assert.ok(options.signal instanceof AbortSignal, 'expected an AbortSignal on the request');
      return { ok: true, json: async () => ({ name: 'Plan' }) };
    },
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      const plan = await ml.generatePlan({});
      assert.equal(plan.name, 'Plan');
    },
  ));

test('a network-level failure is wrapped with the operation, not a bare driver error', () =>
  withFakeFetch(
    async () => {
      throw new TypeError('fetch failed');
    },
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), (err) => {
        assert.match(err.message, /generate-plan/);
        assert.match(err.message, /fetch failed/);
        return true;
      });
    },
  ));

test('an invalid JSON response is wrapped with the operation, not a bare parse error', () =>
  withFakeFetch(
    async () => ({
      ok: true,
      json: async () => {
        throw new SyntaxError('Unexpected token in JSON');
      },
    }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.estimateInjuryRisk({}), (err) => {
        assert.match(err.message, /injury-risk/);
        assert.match(err.message, /Unexpected token/);
        return true;
      });
    },
  ));
