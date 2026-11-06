'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { estimateActivity, perStepFactors } = require('../src/lib/activity-estimate');

// Hand-worked: 1.70 m × 0.414 = 0.7038 m a step; × 6,420 = 4,518.4 m.
// kcal = 0.5 × 70 kg × 4.5184 km = 158.1; active = 6,420 / 100 = 64.2.
test('the spec example, sex unset', () => {
  assert.deepEqual(
    estimateActivity({ steps: 6420, heightCm: 170, weightKg: 70, sex: null }),
    { distanceKm: 4.52, caloriesBurned: 158, activeMinutes: 64, missing: [] },
  );
});

test('stride ratio by sex: 0.415 male, 0.413 female, 0.414 otherwise', () => {
  // 6420 × 1.70 × 0.415 = 4529.3 m → 4.53 km, 158.5 → 159 kcal
  assert.deepEqual(
    estimateActivity({ steps: 6420, heightCm: 170, weightKg: 70, sex: 'male' }),
    { distanceKm: 4.53, caloriesBurned: 159, activeMinutes: 64, missing: [] },
  );
  // 6420 × 1.70 × 0.413 = 4507.5 m → 4.51 km, 157.8 → 158 kcal
  assert.deepEqual(
    estimateActivity({ steps: 6420, heightCm: 170, weightKg: 70, sex: 'female' }),
    { distanceKm: 4.51, caloriesBurned: 158, activeMinutes: 64, missing: [] },
  );
  assert.equal(
    estimateActivity({ steps: 6420, heightCm: 170, weightKg: 70, sex: 'prefer_not_to_say' }).distanceKm,
    4.52,
  );
});

test('DECIMAL strings from MySQL are read as numbers', () => {
  assert.deepEqual(
    estimateActivity({ steps: 6420, heightCm: '170.00', weightKg: '70.00', sex: null }),
    { distanceKm: 4.52, caloriesBurned: 158, activeMinutes: 64, missing: [] },
  );
});

test('no weight: distance but no kcal', () => {
  assert.deepEqual(
    estimateActivity({ steps: 6420, heightCm: 170, weightKg: null, sex: null }),
    { distanceKm: 4.52, caloriesBurned: null, activeMinutes: 64, missing: ['weight'] },
  );
});

test('no height: neither distance nor kcal', () => {
  assert.deepEqual(
    estimateActivity({ steps: 6420, heightCm: null, weightKg: 70, sex: null }),
    { distanceKm: null, caloriesBurned: null, activeMinutes: 64, missing: ['height'] },
  );
  assert.deepEqual(
    estimateActivity({ steps: 100, heightCm: null, weightKg: null, sex: null }).missing,
    ['height', 'weight'],
  );
});

test('zero steps is zero of everything', () => {
  assert.deepEqual(
    estimateActivity({ steps: 0, heightCm: 170, weightKg: 70, sex: null }),
    { distanceKm: 0, caloriesBurned: 0, activeMinutes: 0, missing: [] },
  );
});

const near = (actual, expected) => assert.ok(
  Math.abs(actual - expected) < 1e-12, `${actual} is not ${expected}`,
);

// Per step: 1.70 m × 0.414 / 1000 = 0.0007038 km; kcal 0.5 × 70 × that.
test('per-step factors, sex unset', () => {
  const f = perStepFactors({ heightCm: 170, weightKg: 70, sex: null });
  near(f.distanceKm, 0.0007038);
  near(f.caloriesBurned, 0.024633);
  assert.equal(f.activeMinutes, 0.01);
});

test('per-step factors follow the stride ratio by sex', () => {
  near(perStepFactors({ heightCm: 170, weightKg: 70, sex: 'male' }).distanceKm, 0.0007055);
  near(perStepFactors({ heightCm: 170, weightKg: 70, sex: 'female' }).distanceKm, 0.0007021);
  near(perStepFactors({ heightCm: 170, weightKg: 70, sex: 'male' }).caloriesBurned, 0.0246925);
  near(perStepFactors({ heightCm: '170.00', weightKg: '70.00', sex: null }).caloriesBurned, 0.024633);
});

test('a missing height or weight is a null factor', () => {
  assert.deepEqual(
    perStepFactors({ heightCm: null, weightKg: 70, sex: null }),
    { distanceKm: null, caloriesBurned: null, activeMinutes: 0.01 },
  );
  const noWeight = perStepFactors({ heightCm: 170, weightKg: null, sex: null });
  near(noWeight.distanceKm, 0.0007038);
  assert.equal(noWeight.caloriesBurned, null);
  assert.equal(noWeight.activeMinutes, 0.01);
});

/// The app grows today's figures from the live step count with these factors
/// and this rounding. It can only match the saved day exactly if the server
/// computes the saved day the same way, in the same order of operations: a
/// value sitting on a .5 boundary (100,000 steps at 175 cm and 60 kg is
/// 2,173.5 kcal) otherwise rounds differently on each side.
test('every estimate is the rounding rule applied to the per-step factors', () => {
  const bodies = [[170, 70], [175, 60], [165, 50], [150, 60]];
  for (const sex of [null, 'male', 'female']) {
    for (const [heightCm, weightKg] of bodies) {
      const f = perStepFactors({ heightCm, weightKg, sex });
      for (const steps of [0, 1, 50, 99, 150, 6420, 9630, 100000]) {
        const est = estimateActivity({ steps, heightCm, weightKg, sex });
        const label = `${steps} steps, ${heightCm} cm, ${weightKg} kg, ${sex}`;
        assert.equal(est.distanceKm, Math.round(steps * f.distanceKm * 100) / 100, label);
        assert.equal(est.caloriesBurned, Math.round(steps * f.caloriesBurned), label);
        assert.equal(est.activeMinutes, Math.round(steps * f.activeMinutes), label);
      }
    }
  }
});
