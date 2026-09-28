'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { estimateActivity } = require('../src/lib/activity-estimate');

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
