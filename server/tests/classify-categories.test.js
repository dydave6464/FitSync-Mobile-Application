'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { classifyCategory } = require('../src/db/classify-categories');

const cat = (name) => classifyCategory({ name });

test('a named stretch is a stretch', () => {
  assert.equal(cat('back pec stretch'), 'stretch');
  assert.equal(cat('all fours squad stretch'), 'stretch');
  assert.equal(cat('neck side stretch'), 'stretch');
});

test('a yoga pose is a stretch', () => {
  assert.equal(cat('butterfly yoga pose'), 'stretch');
  assert.equal(cat('seated wide angle pose sequence'), 'stretch');
});

test('joint circles and toe touches are mobility', () => {
  assert.equal(cat('ankle circles'), 'mobility');
  assert.equal(cat('wrist circles'), 'mobility');
  assert.equal(cat('basic toe touch (male)'), 'mobility');
  assert.equal(cat('crab twist toe touch'), 'mobility');
});

test('skill holds and striking are other', () => {
  assert.equal(cat('back lever'), 'other');
  assert.equal(cat('front lever'), 'other');
  assert.equal(cat('front lever reps'), 'other');
  assert.equal(cat('balance board'), 'other');
  assert.equal(cat('left hook. boxing'), 'other');
});

test('first match wins: a name with two signals takes the earlier rule', () => {
  // Contains both 'circles' and 'stretch'. The stretch rule is first.
  assert.equal(cat('circles knee stretch'), 'stretch');
});

test('everything else is strength', () => {
  assert.equal(cat('barbell bench press'), 'strength');
  assert.equal(cat('dumbbell alternate side press'), 'strength');
  assert.equal(cat('3/4 sit-up'), 'strength');
});

// --- Regression guards for the rules measured and REJECTED (spec 4.2). ---
// Each of these looked like a reasonable exclusion pattern and would have
// silently removed real exercises from every plan forever.

test('the `lever` machine prefix stays strength (71 live rows)', () => {
  assert.equal(cat('lever alternate leg press'), 'strength');
  assert.equal(cat('lever bent over row'), 'strength');
  assert.equal(cat('lever seated hip abduction'), 'strength');
  assert.equal(cat('lever assisted chin-up'), 'strength');
});

test('`crunch` stays strength — a `run` pattern matches it (35 live rows)', () => {
  assert.equal(cat('band bicycle crunch'), 'strength');
  assert.equal(cat('cable kneeling crunch'), 'strength');
  assert.equal(cat('band standing twisting crunch'), 'strength');
});

test('rotation exercises stay strength (9 live rows)', () => {
  assert.equal(cat('cable standing shoulder external rotation'), 'strength');
  assert.equal(cat('dumbbell lying external shoulder rotation'), 'strength');
  assert.equal(cat('band lying hip internal rotation'), 'strength');
});

test('balance and hang compounds stay strength', () => {
  assert.equal(cat('dumbbell step up single leg balance with bicep curl'), 'strength');
  assert.equal(cat('kettlebell hang clean'), 'strength');
  assert.equal(cat('kettlebell bottoms up clean from the hang position'), 'strength');
});

test('kick compounds stay strength (all 4 live rows)', () => {
  assert.equal(cat('outside leg kick push-up'), 'strength');
  assert.equal(cat('push-up inside leg kick'), 'strength');
  assert.equal(cat('exercise ball one legged diagonal kick hamstring curl'), 'strength');
  assert.equal(cat('kick out sit'), 'strength');
});

test('walking lunge stays strength', () => {
  assert.equal(cat('walking lunge'), 'strength');
});

test('`outstretched` is not a stretch: the pattern needs a word-start boundary (live row 1146)', () => {
  assert.equal(cat('single leg bridge with outstretched leg'), 'strength');
});

test('the word-start boundary still catches every real stretch form', () => {
  assert.equal(cat('back pec stretch'), 'stretch');
  assert.equal(cat('hamstring stretches'), 'stretch');
  assert.equal(cat('standing quad stretching'), 'stretch');
});
