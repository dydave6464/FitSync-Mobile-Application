'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { isPlannedWorkoutDay } = require('../src/lib/workout-day');

test('a chosen training day with an active plan is a workout day', () => {
  assert.equal(
    isPlannedWorkoutDay({ hasActivePlan: true, trainingDays: [1, 3, 5], weekday: 3 }),
    true,
  );
});

test('a day that is not chosen is not', () => {
  assert.equal(
    isPlannedWorkoutDay({ hasActivePlan: true, trainingDays: [1, 3, 5], weekday: 2 }),
    false,
  );
});

test('with no days chosen, every day is', () => {
  for (let weekday = 1; weekday <= 7; weekday += 1) {
    assert.equal(
      isPlannedWorkoutDay({ hasActivePlan: true, trainingDays: [], weekday }),
      true,
      `weekday ${weekday}`,
    );
  }
});

test('without an active plan, no day is', () => {
  assert.equal(isPlannedWorkoutDay({ hasActivePlan: false, trainingDays: [], weekday: 1 }), false);
  assert.equal(
    isPlannedWorkoutDay({ hasActivePlan: false, trainingDays: [1, 2, 3], weekday: 1 }),
    false,
  );
});
