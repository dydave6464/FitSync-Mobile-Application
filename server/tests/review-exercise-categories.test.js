'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { buildReport, BROAD } = require('../scripts/review-exercise-categories');

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

test('BROAD also matches gerund forms, not just the bare stem', () => {
  assert.match('hanging leg raise', BROAD, 'hanging should match the hang stem');
  assert.match('twisting lunge', BROAD, 'twisting should match the twist stem');
});

test('ruleFor normalizes the same way classifyCategory does, so an anchored rule still resolves with surrounding whitespace', () => {
  const md = buildReport([{ exercise_id: 7, name: '  balance board  ', muscle_group: 'core' }]);
  assert.match(md, /\*\*other\*\*/, 'demoted via the balance board rule');
  assert.match(md, /\/\^balance board\$\//, 'the rule column must resolve, not fall back to empty');
});

test('a row that is both demoted and a broad signal is listed only in section A', () => {
  const md = buildReport([...rows, { exercise_id: 6, name: 'hanging pike stretch', muscle_group: 'abs' }]);
  assert.match(md, /hanging pike stretch/, 'the demoted row should appear');
  assert.match(md, /Demoted \(3\)/, 'demoted count includes the new row');
  assert.match(md, /Flagged, not demoted \(2\)/, 'flagged count must NOT also include it');
});

test('BROAD keeps matching any word beginning with roll, including fused forms like rollerout', () => {
  assert.match('band assisted wheel rollerout', BROAD);
  assert.match('barbell rollerout', BROAD);
  assert.match('barbell rollerout from bench', BROAD);
  assert.match('barbell standing ab rollerout', BROAD);
  assert.match('foam rolling', BROAD, 'rolling must still match');
  assert.match('ab rollout', BROAD, 'rollout must still match');
});

test('section C lists a manual override alongside what the classifier would say', () => {
  // Pinned to stretch by a human even though the classifier calls it strength.
  const manual = [{ exercise_id: 42, name: 'single leg bridge with outstretched leg', category: 'stretch' }];
  const md = buildReport(rows, manual);
  assert.match(md, /## C\. Manual overrides \(1\)/);
  assert.match(md, /42/);
  assert.match(md, /single leg bridge with outstretched leg/);
  assert.match(md, /stretch/, 'the stored category must appear');
  assert.match(md, /strength/, "the classifier's own opinion must appear too");
});

test('section C still renders, with a count of 0, when there are no manual rows', () => {
  const md = buildReport(rows);
  assert.match(md, /## C\. Manual overrides \(0\)/);
});
