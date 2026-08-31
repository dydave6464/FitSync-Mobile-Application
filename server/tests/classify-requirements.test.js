'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { classifyRequirements } = require('../src/db/classify-requirements');

const req = (name, equipment) => classifyRequirements({ name, equipment });

test('a free-weight exercise naming a bench requires one', () => {
  assert.deepEqual(req('barbell bench press', 'barbell'), ['bench']);
  assert.deepEqual(req('dumbbell incline bench press', 'dumbbell'), ['bench']);
});

test('a free-weight incline, decline or lying exercise requires a bench', () => {
  assert.deepEqual(req('dumbbell incline fly', 'dumbbell'), ['bench']);
  assert.deepEqual(req('barbell lying close-grip press', 'barbell'), ['bench']);
  assert.deepEqual(req('ez barbell decline triceps extension', 'ez barbell'), ['bench']);
});

test('a machine station provides its own pad, so it requires no user bench', () => {
  // Gating these would lock a gym-goer out of a station that already has a
  // bench built into it. They are already behind the 'machines' option.
  assert.deepEqual(req('smith incline bench press', 'smith machine'), []);
  assert.deepEqual(req('lever incline chest press', 'leverage machine'), []);
  assert.deepEqual(req('cable incline fly', 'cable'), []);
});

test('a bodyweight pull-up or chin-up requires a bar', () => {
  assert.deepEqual(req('pull-up', 'body weight'), ['pull-up bar']);
  assert.deepEqual(req('wide grip pull-up', 'body weight'), ['pull-up bar']);
  assert.deepEqual(req('chin-up', 'body weight'), ['pull-up bar']);
  assert.deepEqual(req('l-pull-up', 'body weight'), ['pull-up bar']);
});

test('a bodyweight exercise naming a bench requires one', () => {
  assert.deepEqual(req('bench dip (knees bent)', 'body weight'), ['bench']);
  assert.deepEqual(req('inverted row on bench', 'body weight'), ['bench']);
});

test('a bodyweight incline or decline is a box or the floor, not a bench', () => {
  // The line the design draws: an explicit "bench" in the name means the gear;
  // incline/decline alone does not.
  assert.deepEqual(req('incline push-up (on box)', 'body weight'), []);
  assert.deepEqual(req('decline sit-up', 'body weight'), []);
  assert.deepEqual(req('decline push-up', 'body weight'), []);
});

test('curated overrides beat the patterns', () => {
  // Says bench, needs none.
  assert.deepEqual(req('bench dip on floor', 'body weight'), []);
  // Says pull-up, but it is a row off a bench.
  assert.deepEqual(req('bench pull-ups', 'body weight'), ['bench']);
  // Says pull-up, but the gear is a cable station.
  assert.deepEqual(req('inverse leg curl (on pull-up cable machine)', 'body weight'), ['machines']);
});

test('an ordinary exercise requires nothing extra', () => {
  assert.deepEqual(req('dumbbell biceps curl', 'dumbbell'), []);
  assert.deepEqual(req('push-up', 'body weight'), []);
  assert.deepEqual(req('barbell deadlift', 'barbell'), []);
});

test('classification is case-insensitive and tolerates odd input', () => {
  assert.deepEqual(req('BARBELL BENCH PRESS', 'BARBELL'), ['bench']);
  assert.deepEqual(req('push-up', null), []);
});
