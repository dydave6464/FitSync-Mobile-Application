'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { matchItems, MAX_CARDS } = require('../src/lib/photo-match');

const food = (foodId, name, servingDesc = '1 cup (160 g)') => ({ foodId, name, servingDesc, kcal: 100, proteinG: 1, carbsG: 1, fatG: 1, externalId: null });
const MENU = [
  food(1, 'White rice'), food(2, 'Garlic fried rice (sinangag)'), food(3, 'Sinigang na baboy', '1 bowl (300 g)'),
  food(4, 'Tinola', '1 bowl (300 g)'), food(5, 'Fried egg', '1 piece (50 g)'),
];
const raw = (o) => ({ menu: null, name: o.menu ?? 'x', quantity: null, unit: null, grams: null, confidence: 0.8, alternatives: [], ...o });

test('names match menu foods ignoring case; "name" is tried when "menu" is missing', () => {
  const { items, unlisted } = matchItems([
    raw({ menu: 'white RICE', grams: 240 }),
    raw({ menu: null, name: 'fried egg', grams: 50 }),
  ], MENU);
  assert.deepEqual(items.map((i) => [i.food.foodId, i.servings]), [[1, 1.5], [5, 1]]);
  assert.deepEqual(unlisted, []);
});

test('a menu name with a line break matches the one-line name the AI was shown', () => {
  const menu = [food(9, 'Pork\nadobo'), food(10, 'Chicken\r\n\tinasal')];
  const { items, unlisted } = matchItems([
    raw({ menu: 'Pork adobo', alternatives: ['chicken inasal'] }),
  ], menu);
  assert.deepEqual(items.map((i) => [i.food.foodId, i.alternatives.map((a) => a.foodId)]), [[9, [10]]]);
  assert.deepEqual(unlisted, []);
});

test('an item matching nothing is unlisted, once per name', () => {
  const { items, unlisted } = matchItems([
    raw({ menu: null, name: 'Atchara (pickled papaya)', confidence: 0.4 }),
    raw({ menu: 'Not on the menu', name: 'atchara (pickled papaya)' }),
  ], MENU);
  assert.deepEqual(items, []);
  assert.deepEqual(unlisted, [{ name: 'Atchara (pickled papaya)', confidence: 0.4 }]);
});

test('two items naming one food merge, servings added, capped at 10', () => {
  const { items } = matchItems([
    raw({ menu: 'White rice', grams: 160, alternatives: ['Garlic fried rice (sinangag)'] }),
    raw({ menu: 'White rice', grams: 80, alternatives: [] }),
  ], MENU);
  assert.equal(items.length, 1);
  assert.equal(items[0].servings, 1.5);
  assert.deepEqual(items[0].alternatives.map((a) => a.foodId), [2], 'the first item\'s alternatives are kept');
  const big = matchItems([raw({ menu: 'White rice', grams: 1500 }), raw({ menu: 'White rice', grams: 1500 })], MENU);
  assert.equal(big.items[0].servings, 10);
});

test('alternatives: other menu foods only, no repeats, at most two', () => {
  const { items } = matchItems([raw({
    menu: 'Sinigang na baboy',
    alternatives: ['Sinigang na baboy', 'Unknown soup', 'tinola', 'Tinola', 'White rice', 'Fried egg'],
  })], MENU);
  assert.deepEqual(items[0].alternatives.map((a) => a.foodId), [4, 1]);
});

test(`at most ${MAX_CARDS} cards in all, in the AI's order`, () => {
  const many = Array.from({ length: 12 }, (_, i) => raw({ menu: null, name: `Dish ${i}` }));
  const { items, unlisted } = matchItems([raw({ menu: 'White rice' }), ...many], MENU);
  assert.equal(items.length + unlisted.length, 8);
  assert.equal(unlisted.at(-1).name, 'Dish 6');
});
