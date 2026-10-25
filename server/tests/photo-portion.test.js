'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { servingGrams, estimateServings } = require('../src/lib/photo-portion');

test('servingGrams reads the last "(N g)", "(~N g)" or "(N ml)"', () => {
  assert.equal(servingGrams('1 cup (160 g)'), 160);
  assert.equal(servingGrams('1 stick, 10 pcs (~100 g) with sauce'), 100);
  assert.equal(servingGrams('1/4 cup (60 ml)'), 60);
  assert.equal(servingGrams('1 stick, 5 pieces with sauce (95 g)'), 95);
  assert.equal(servingGrams('1 sachet (20 g) in 1 glass (240 ml)'), 240);
  assert.equal(servingGrams('1 serving (12.5 g)'), 12.5);
  assert.equal(servingGrams('1 piece'), null);
  assert.equal(servingGrams('2 pcs, 30 g each'), null);
  assert.equal(servingGrams(null), null);
});

test('grams over the serving\'s grams, to the nearest half, 0.5 to 10', () => {
  assert.equal(estimateServings({ grams: 240, quantity: 1, unit: 'cup' }, '1 cup (160 g)'), 1.5);
  assert.equal(estimateServings({ grams: 150, quantity: 1, unit: 'cup' }, '1 cup (160 g)'), 1);
  assert.equal(estimateServings({ grams: 200, quantity: null, unit: null }, '1 cup (160 g)'), 1.5); // 1.25 rounds up
  assert.equal(estimateServings({ grams: 20, quantity: null, unit: null }, '1 cup (160 g)'), 0.5); // floor
  assert.equal(estimateServings({ grams: 5000, quantity: null, unit: null }, '1 cup (160 g)'), 10); // ceiling
});

test('without grams in the serving: the AI\'s quantity when its unit matches the serving\'s first word', () => {
  assert.equal(estimateServings({ grams: 90, quantity: 3, unit: 'pieces' }, '1 piece'), 3);
  assert.equal(estimateServings({ grams: 90, quantity: 3, unit: 'pcs' }, '2 pieces'), 1.5);
  assert.equal(estimateServings({ grams: 300, quantity: 2, unit: 'glass' }, '1 glass'), 2);
  assert.equal(estimateServings({ grams: 300, quantity: 2, unit: 'Glasses' }, '1 glass'), 2);
  assert.equal(estimateServings({ grams: 30, quantity: 1, unit: 'cup' }, '1/2 cup'), 2);
  assert.equal(estimateServings({ grams: 90, quantity: 3, unit: 'slice' }, '1 piece'), 1, 'units differ: 1');
  assert.equal(estimateServings({ grams: null, quantity: null, unit: null }, '1 piece'), 1);
});

test('grams in the serving but none from the AI fall back to the quantity, then 1', () => {
  assert.equal(estimateServings({ grams: null, quantity: 2, unit: 'cup' }, '1 cup (160 g)'), 2);
  assert.equal(estimateServings({ grams: 0, quantity: null, unit: null }, '1 cup (160 g)'), 1);
});
