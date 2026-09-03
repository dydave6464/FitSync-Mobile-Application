'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { buildReport } = require('../scripts/review-exercise-categories');

const rows = [
  { exercise_id: 1, name: 'barbell bench press', muscle_group: 'pectorals' },
  { exercise_id: 2, name: 'back pec stretch', muscle_group: 'lats' },
  { exercise_id: 3, name: 'ankle circles', muscle_group: 'calves' },
  { exercise_id: 4, name: 'barbell standing twist', muscle_group: 'abs' },
  { exercise_id: 5, name: 'kettlebell hang clean', muscle_group: 'glutes' },
];

test('the report lists every demoted row', () => {
  const md = buildReport(rows);
  assert.match(md, /back pec stretch/);
  assert.match(md, /ankle circles/);
});

test('the report flags broad-signal rows that were NOT demoted', () => {
  const md = buildReport(rows);
  assert.match(md, /barbell standing twist/, 'twist is a broad signal');
  assert.match(md, /kettlebell hang clean/, 'hang is a broad signal');
});

test('a plain strength exercise appears in neither section', () => {
  const md = buildReport(rows);
  assert.ok(!md.includes('barbell bench press'), 'no signal, nothing to review');
});

test('the report states both section counts', () => {
  const md = buildReport(rows);
  assert.match(md, /Demoted \(2\)/);
  assert.match(md, /Flagged, not demoted \(2\)/);
});
