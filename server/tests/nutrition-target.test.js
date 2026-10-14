'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { dailyTarget, ageOn } = require('../src/lib/nutrition-target');
const parity = require('./fixtures/daily-targets-parity.json');

const MAN = {
  sex: 'male', dateOfBirth: '1996-01-15', heightCm: 175, weightKg: 70,
  activityLevel: 'moderate', mainGoal: 'build_muscle',
};

test('build muscle adds 250 to rounded maintenance; macros follow', () => {
  // BMR 1648.75 x 1.55 = 2555.6 -> 2550; +250 = 2800. Protein 112 -> 110.
  // Fat round(2800*0.25/9) = 78. Carbs round((2800-440-702)/4) = 415.
  // Fiber round(14*2800/1000) = 39 -> capped at 38 (IOM adult men max).
  assert.deepEqual(dailyTarget(MAN, '2026-10-14'), {
    target: { kcal: 2800, proteinG: 110, carbsG: 415, fatG: 78, fiberG: 38 }, missing: [],
  });
});

test('lose weight subtracts 500 but never goes below the floor', () => {
  const small = {
    sex: 'female', dateOfBirth: '1996-01-15', heightCm: 150, weightKg: 45,
    activityLevel: 'sedentary', mainGoal: 'lose_weight',
  };
  // Maintenance 1300 - 500 = 800 -> floor 1200. Protein 72 -> 70. Fat 33. Carbs 156.
  // Fiber round(14*1200/1000) = 17 -> floored at 25 (PDRI/FDA label minimum).
  assert.deepEqual(dailyTarget(small, '2026-10-14').target,
    { kcal: 1200, proteinG: 70, carbsG: 156, fatG: 33, fiberG: 25 });
  const man = { ...MAN, heightCm: 150, weightKg: 45, activityLevel: 'sedentary', mainGoal: 'lose_weight' };
  assert.equal(dailyTarget(man, '2026-10-14').target.kcal, 1500);
});

test('fiber follows the goal-adjusted kcal at 14 g per 1,000 kcal', () => {
  // Female, 45kg, 150cm, age 30, active (1.725): BMR 1076.5 x 1.725 = 1857.06
  // -> maintenance 1850. Fiber round(14*1850/1000) = round(25.9) = 26.
  const profile = {
    sex: 'female', dateOfBirth: '1996-01-15', heightCm: 150, weightKg: 45,
    activityLevel: 'active', mainGoal: 'general_fitness',
  };
  const { target } = dailyTarget(profile, '2026-10-14');
  assert.equal(target.kcal, 1850);
  assert.equal(target.fiberG, 26);
});

test('endurance, general fitness and no goal keep maintenance', () => {
  for (const mainGoal of ['improve_endurance', 'general_fitness', null]) {
    assert.equal(dailyTarget({ ...MAN, mainGoal }, '2026-10-14').target.kcal, 2550);
  }
});

test('a birthday still to come this year is not counted yet', () => {
  assert.equal(ageOn('1996-10-15', '2026-10-14'), 29);
  assert.equal(ageOn('1996-10-14', '2026-10-14'), 30);
  assert.equal(ageOn('1996-01-15', '2026-10-14'), 30);
  assert.equal(ageOn('2000-02-29', '2026-02-28'), 25);
});

test('no target, and the missing fields named, when the profile is incomplete', () => {
  assert.deepEqual(
    dailyTarget({ ...MAN, sex: 'prefer_not_to_say', weightKg: null, heightCm: null }, '2026-10-14'),
    { target: null, missing: ['sex', 'heightCm', 'weightKg'] },
  );
  assert.deepEqual(
    dailyTarget({ sex: null, dateOfBirth: null, heightCm: null, weightKg: null, activityLevel: null, mainGoal: null }, '2026-10-14').missing,
    ['sex', 'dateOfBirth', 'heightCm', 'weightKg', 'activityLevel'],
  );
});

test('maintenance agrees with the app onboarding estimate (shared fixture)', () => {
  for (const c of parity) {
    const { target } = dailyTarget({ ...c, mainGoal: 'general_fitness' }, c.today);
    assert.equal(target.kcal, c.kcal, `kcal for ${JSON.stringify(c)}`);
    assert.equal(target.proteinG, c.proteinG, `protein for ${JSON.stringify(c)}`);
  }
});
