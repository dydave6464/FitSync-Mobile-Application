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
        mainGoal: 'lose_weight', fitnessLevel: 'beginner', trainingLocation: null,
        healthCaution: false, equipment: [], injuries: [], goals: [], overrides: { daysPerWeek: 3 },
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

const DETAIL_ONE = 'No exercises could be selected for day 3 (Legs) of the push_pull_legs split. '
  + 'If the catalogue is seeded, the reported injuries and available equipment leave nothing suitable for it.';
const DETAIL_TWO = 'No exercises could be selected for day 2 (Pull) and day 3 (Legs) of the push_pull_legs split. '
  + 'If the catalogue is seeded, the reported injuries and available equipment leave nothing suitable for it.';
const DETAIL_FULL_BODY = 'No exercises could be selected for day 1 (Full body) of the full_body split. '
  + 'If the catalogue is seeded, the reported injuries and available equipment leave nothing suitable for it.';

test('an unfillable plan day becomes a readable 422 naming the day', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 503, json: async () => ({ detail: DETAIL_ONE }) }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), (err) => {
        assert.equal(err.status, 422);
        assert.equal(err.code, 'UNFILLABLE_PLAN_DAY');
        assert.equal(
          err.message,
          'Nothing suitable for the Legs day with your injuries and equipment. '
            + 'Try Full body, or add equipment.',
        );
        return true;
      });
    },
  ));

test('two unfillable days are both named', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 503, json: async () => ({ detail: DETAIL_TWO }) }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), (err) => {
        assert.match(err.message, /^Nothing suitable for the Pull and Legs days /);
        return true;
      });
    },
  ));

test('Full body as the only unfillable day gets its own suggestion', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 503, json: async () => ({ detail: DETAIL_FULL_BODY }) }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), (err) => {
        assert.equal(err.status, 422);
        assert.equal(err.code, 'UNFILLABLE_PLAN_DAY');
        assert.equal(
          err.message,
          'Nothing suitable for the Full body day with your injuries and equipment. '
            + 'Try adding equipment.',
        );
        return true;
      });
    },
  ));

const BEGINNER_CLAUSE = ' Only exercises marked beginner-friendly were considered (fitness level or health check).';
const DETAIL_BEGINNER = 'No exercises could be selected for day 2 (Pull) of the push_pull_legs split.'
  + `${BEGINNER_CLAUSE} If the catalogue is seeded, the reported injuries and available equipment leave nothing suitable for it.`;
const DETAIL_BEGINNER_FULL_BODY = 'No exercises could be selected for day 1 (Full body) of the full_body split.'
  + `${BEGINNER_CLAUSE} If the catalogue is seeded, the reported injuries and available equipment leave nothing suitable for it.`;

test('a beginner day that cannot be filled says nothing beginner-friendly was found', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 503, json: async () => ({ detail: DETAIL_BEGINNER }) }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), (err) => {
        assert.equal(err.status, 422);
        assert.equal(err.code, 'UNFILLABLE_PLAN_DAY');
        assert.equal(
          err.message,
          'Nothing beginner-friendly for the Pull day with your equipment yet. '
            + 'Try Full body, or add equipment.',
        );
        return true;
      });
    },
  ));

test('a beginner Full body day keeps its own suggestion', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 503, json: async () => ({ detail: DETAIL_BEGINNER_FULL_BODY }) }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), (err) => {
        assert.equal(
          err.message,
          'Nothing beginner-friendly for the Full body day with your equipment yet. '
            + 'Try adding equipment.',
        );
        return true;
      });
    },
  ));

test('unseeded preferences stay an internal error', () =>
  withFakeFetch(
    async () => ({
      ok: false,
      status: 503,
      json: async () => ({
        detail: 'Exercise preferences are not loaded: run `npm run seed:preferences` in server/ '
          + 'before generating plans for beginners.',
      }),
    }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), (err) => {
        assert.equal(err.code, undefined);
        assert.match(err.message, /responded 503/);
        return true;
      });
    },
  ));

test('any other 503 stays an internal error', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 503, json: async () => ({ detail: 'model loading' }) }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), (err) => {
        assert.equal(err.code, undefined);
        assert.match(err.message, /responded 503/);
        return true;
      });
    },
  ));

test('a 503 whose body is not JSON stays an internal error', () =>
  withFakeFetch(
    async () => ({ ok: false, status: 503, json: async () => { throw new SyntaxError('bad'); } }),
    async () => {
      const ml = httpClient.create('http://localhost:8000');
      await assert.rejects(() => ml.generatePlan({}), /responded 503/);
    },
  ));
