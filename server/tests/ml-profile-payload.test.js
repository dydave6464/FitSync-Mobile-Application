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
    activityLevel: 'moderately_active',
    equipment: [{ equipmentId: 41, name: 'Dumbbell' }],
    injuries: [{
      injuryId: 3, name: 'Knee', isLateral: true, regionGroup: 'lower_body', side: 'left',
    }],
  });
});

test('no personal field survives, however it is spelled in the profile', () => {
  const sent = JSON.stringify(toPlanPayload(PROFILE));
  for (const value of ['juan@example.com', 'Juan Dela Cruz', 'Cebu City', '1999-04-02', '172', '68.5']) {
    assert.ok(!sent.includes(value), `${value} was sent`);
  }
  for (const key of ['userId', 'email', 'fullName', 'city', 'dateOfBirth', 'sex', 'heightCm',
    'weightKg', 'goalWeightKg', 'trainingLocation', 'isPremium', 'notificationsEnabled',
    'onboardingCompleted', 'joinedAt', 'trainingDays', 'weightUnit']) {
    assert.ok(!(key in toPlanPayload(PROFILE)), `${key} was sent`);
  }
});

test("the generator screen's choices pass through when given", () => {
  const overrides = { daysPerWeek: 4, splitStyle: 'upper_lower', sessionLengthMin: 45 };
  assert.deepEqual(toPlanPayload({ ...PROFILE, overrides }).overrides, overrides);
  assert.ok(!('overrides' in toPlanPayload(PROFILE)), 'no overrides key when none were chosen');
});

test('a sparse profile maps without inventing values', () => {
  assert.deepEqual(toPlanPayload({}), {
    mainGoal: null, fitnessLevel: null, activityLevel: null, equipment: [], injuries: [],
  });
});

test('a risk request carries each check-in\'s answers and date, not its row id', () => {
  const checkin = {
    checkinId: 12, checkinDate: '2026-09-24', sleepQuality: 'good',
    muscleSoreness: 'mild', energy: 'high', stress: 'low', userId: 7,
  };
  assert.deepEqual(toRiskPayload({ checkins: [checkin], load: 12.5, injuryHistory: [] }), {
    checkins: [{
      checkinDate: '2026-09-24', sleepQuality: 'good', muscleSoreness: 'mild',
      energy: 'high', stress: 'low',
    }],
    load: 12.5,
    injuryHistory: [],
  });
});
