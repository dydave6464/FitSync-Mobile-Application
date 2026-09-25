'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { GROUPS, groupOf } = require('../src/lib/muscle-groups');

// Every muscle_group the live catalogue carries, as of 2026-09-25.
const CATALOGUE = [
  'biceps', 'pectorals', 'abs', 'delts', 'triceps', 'glutes', 'upper back',
  'lats', 'calves', 'quads', 'forearms', 'hamstrings', 'spine', 'traps',
  'serratus anterior', 'adductors', 'abductors', 'levator scapulae',
];

test('the six groups, in body order', () => {
  assert.deepEqual(GROUPS, ['chest', 'back', 'shoulders', 'arms', 'legs', 'core']);
});

test('every catalogue muscle belongs to one of them', () => {
  for (const muscle of CATALOGUE) {
    assert.ok(GROUPS.includes(groupOf(muscle)), muscle);
  }
});

test('each muscle lands where a person would look for it', () => {
  const cases = [
    ['pectorals', 'chest'], ['serratus anterior', 'chest'],
    ['upper back', 'back'], ['lats', 'back'], ['traps', 'back'], ['spine', 'back'],
    ['levator scapulae', 'back'],
    ['delts', 'shoulders'],
    ['biceps', 'arms'], ['triceps', 'arms'], ['forearms', 'arms'],
    ['quads', 'legs'], ['hamstrings', 'legs'], ['glutes', 'legs'], ['calves', 'legs'],
    ['adductors', 'legs'], ['abductors', 'legs'],
    ['abs', 'core'],
  ];
  for (const [muscle, group] of cases) assert.equal(groupOf(muscle), group, muscle);
});

test('a muscle outside the map has no group', () => {
  assert.equal(groupOf('cardiovascular system'), null);
});
