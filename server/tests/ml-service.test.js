'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createMlService } = require('../src/services/ml');

const RISK_LEVELS = ['low', 'moderate', 'high'];
const SPLITS = ['full_body', 'upper_lower', 'push_pull_legs', 'bro_split'];

test('stub mode is the default', () => {
  const ml = createMlService({ mode: undefined });
  assert.equal(typeof ml.generatePlan, 'function');
  assert.equal(typeof ml.estimateInjuryRisk, 'function');
});

test('generatePlan returns a plan matching the workout_plans shape', async () => {
  const ml = createMlService({ mode: 'stub' });
  const plan = await ml.generatePlan({ splitStyle: 'upper_lower', daysPerWeek: 4, sessionLengthMin: 60 });

  assert.equal(typeof plan.name, 'string');
  assert.ok(SPLITS.includes(plan.splitStyle));
  assert.equal(plan.splitStyle, 'upper_lower');
  assert.equal(plan.daysPerWeek, 4);
  assert.equal(plan.sessionLengthMin, 60);
  assert.ok(Array.isArray(plan.exercises));
  assert.ok(plan.exercises.length > 0);

  for (const ex of plan.exercises) {
    assert.equal(typeof ex.name, 'string');
    assert.equal(typeof ex.orderNo, 'number');
    assert.equal(typeof ex.targetSets, 'number');
    assert.equal(typeof ex.targetReps, 'string');
  }
});

test('generatePlan honours FR-2.3 preferences it is given', async () => {
  const ml = createMlService({ mode: 'stub' });
  const plan = await ml.generatePlan({ splitStyle: 'push_pull_legs', daysPerWeek: 6, sessionLengthMin: 30 });
  assert.equal(plan.splitStyle, 'push_pull_legs');
  assert.equal(plan.daysPerWeek, 6);
  assert.equal(plan.sessionLengthMin, 30);
});

test('generatePlan falls back to safe defaults for a bare profile', async () => {
  const ml = createMlService({ mode: 'stub' });
  const plan = await ml.generatePlan({});
  assert.ok(SPLITS.includes(plan.splitStyle));
  assert.ok(plan.daysPerWeek >= 1 && plan.daysPerWeek <= 7);
});

test('estimateInjuryRisk returns a valid enum level and numeric score', async () => {
  const ml = createMlService({ mode: 'stub' });
  const result = await ml.estimateInjuryRisk({ checkins: [], load: 0, injuryHistory: [] });
  assert.ok(RISK_LEVELS.includes(result.riskLevel));
  assert.equal(typeof result.trainingLoadScore, 'number');
});

test('estimateInjuryRisk stays conservative with no data (FR-5.2, C-6)', async () => {
  const ml = createMlService({ mode: 'stub' });
  const result = await ml.estimateInjuryRisk({ checkins: [], load: 0, injuryHistory: [] });
  assert.equal(result.riskLevel, 'low');
});

test('http mode without a service URL fails loudly at construction', () => {
  assert.throws(
    () => createMlService({ mode: 'http', serviceUrl: null }),
    /ML_SERVICE_URL/,
  );
});

test('http mode with a URL builds a client exposing the same interface', () => {
  const ml = createMlService({ mode: 'http', serviceUrl: 'http://localhost:8000' });
  assert.equal(typeof ml.generatePlan, 'function');
  assert.equal(typeof ml.estimateInjuryRisk, 'function');
});

test('an unknown mode is rejected rather than silently stubbed', () => {
  assert.throws(() => createMlService({ mode: 'magic' }), /magic/);
});
