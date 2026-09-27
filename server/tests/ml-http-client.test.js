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

test('generatePlan sends the mapped profile, never the personal fields', () => {
  let body;
  return withFakeFetch(
    async (_url, options) => {
      body = JSON.parse(options.body);
      return { ok: true, json: async () => ({ name: 'Plan' }) };
    },
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await ml.generatePlan({
        userId: 7, email: 'juan@example.com', fullName: 'Juan Dela Cruz', city: 'Cebu City',
        dateOfBirth: '1999-04-02', heightCm: 172, weightKg: 68.5,
        mainGoal: 'lose_weight', fitnessLevel: 'beginner', activityLevel: 'lightly_active',
        equipment: [], injuries: [], overrides: { daysPerWeek: 3 },
      });
      assert.deepEqual(body, {
        mainGoal: 'lose_weight', fitnessLevel: 'beginner',
        equipment: [], injuries: [], overrides: { daysPerWeek: 3 },
      });
    },
  );
});

test('estimateInjuryRisk sends the mapped check-ins', () => {
  let body;
  return withFakeFetch(
    async (_url, options) => {
      body = JSON.parse(options.body);
      return { ok: true, json: async () => ({ riskLevel: 'low', trainingLoadScore: 4 }) };
    },
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await ml.estimateInjuryRisk({
        checkins: [{
          checkinId: 12, checkinDate: '2026-09-24', sleepQuality: 'good',
          muscleSoreness: 'none', energy: 'high', stress: 'low',
        }],
        load: 0,
        injuryHistory: [],
      });
      assert.deepEqual(body, {
        checkins: [{ sleepQuality: 'good', muscleSoreness: 'none', energy: 'high', stress: 'low' }],
        load: 0,
        injuryHistory: [],
      });
    },
  );
});
