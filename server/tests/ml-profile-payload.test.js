'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { toPlanPayload, toRiskPayload } = require('../src/services/ml/profile-payload');

/// A profile as getProfile returns it, with every personal field filled in.
const PROFILE = {
  userId: 7,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  city: 'Cebu City',
  dateOfBirth: '1999-04-02',
  sex: 'male',
  heightCm: 172,
  weightKg: 68.5,
  goalWeightKg: 65,
  weightUnit: 'kg',
  trainingLocation: 'home',
  isPremium: false,
  notificationsEnabled: true,
  onboardingCompleted: true,
  joinedAt: 1758000000,
  trainingDays: [1, 3, 5],
  mainGoal: 'build_muscle',
  fitnessLevel: 'beginner',
  activityLevel: 'moderately_active',
  equipment: [{ equipmentId: 41, name: 'Dumbbell', extra: 'x' }],
  injuries: [{
    injuryId: 3, name: 'Knee', isLateral: true, regionGroup: 'lower_body', side: 'left', notes: 'x',
  }],
};

test('a plan request carries only what the generator reads', () => {
  assert.deepEqual(toPlanPayload(PROFILE), {
    mainGoal: 'build_muscle',
    fitnessLevel: 'beginner',
    equipment: [{ equipmentId: 41 }],
    injuries: [{ injuryId: 3, regionGroup: 'lower_body' }],
  });
});

test('no personal or unread field survives, by key or by value', () => {
  const sent = JSON.stringify(toPlanPayload(PROFILE));
  for (const value of ['juan@example.com', 'Juan Dela Cruz', 'Cebu City', '1999-04-02', '172',
    '68.5', 'moderately_active', 'Dumbbell', 'Knee', 'left']) {
    assert.ok(!sent.includes(value), `${value} was sent`);
  }
  for (const key of ['userId', 'email', 'fullName', 'city', 'dateOfBirth', 'sex', 'heightCm',
    'weightKg', 'goalWeightKg', 'trainingLocation', 'isPremium', 'notificationsEnabled',
    'onboardingCompleted', 'joinedAt', 'trainingDays', 'weightUnit', 'activityLevel']) {
    assert.ok(!(key in toPlanPayload(PROFILE)), `${key} was sent`);
  }
});

test("the generator screen's three choices pass through, and nothing else inside them", () => {
  const overrides = { daysPerWeek: 4, splitStyle: 'upper_lower', sessionLengthMin: 45 };
  assert.deepEqual(toPlanPayload({ ...PROFILE, overrides }).overrides, overrides);
  assert.deepEqual(
    toPlanPayload({ ...PROFILE, overrides: { daysPerWeek: 3, email: 'a@b.c' } }).overrides,
    { daysPerWeek: 3 },
  );
  // Regenerate sends {} when nothing was chosen; that stays an empty object.
  assert.deepEqual(toPlanPayload({ ...PROFILE, overrides: {} }).overrides, {});
  assert.ok(!('overrides' in toPlanPayload(PROFILE)), 'no overrides key when none were chosen');
  assert.ok(!('overrides' in toPlanPayload({ ...PROFILE, overrides: 'x' })), 'not an object');
});

test('a sparse or missing profile maps without inventing values or throwing', () => {
  const empty = { mainGoal: null, fitnessLevel: null, equipment: [], injuries: [] };
  assert.deepEqual(toPlanPayload({}), empty);
  assert.deepEqual(toPlanPayload(null), empty);
  assert.deepEqual(toPlanPayload(undefined), empty);
  assert.deepEqual(toPlanPayload({ equipment: {}, injuries: null }), empty);
});

test('a risk request carries each check-in\'s four answers, not its id or date', () => {
  const checkin = {
    checkinId: 12, checkinDate: '2026-09-24', sleepQuality: 'good',
    muscleSoreness: 'mild', energy: 'high', stress: 'low', userId: 7,
  };
  const injury = { injuryId: 3, name: 'Knee', isLateral: true, regionGroup: 'lower_body', side: 'left' };
  assert.deepEqual(toRiskPayload({ checkins: [checkin], load: 12.5, injuryHistory: [injury] }), {
    checkins: [{ sleepQuality: 'good', muscleSoreness: 'mild', energy: 'high', stress: 'low' }],
    load: 12.5,
    injuryHistory: [{ injuryId: 3, regionGroup: 'lower_body' }],
  });
});

test('a missing or sparse risk request maps without throwing', () => {
  const empty = { checkins: [], load: 0, injuryHistory: [] };
  assert.deepEqual(toRiskPayload(undefined), empty);
  assert.deepEqual(toRiskPayload({ checkins: null, injuryHistory: null }), empty);
});
