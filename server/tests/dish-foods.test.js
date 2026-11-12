'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { DISH_FOODS, SIDE_FOODS, missingDishFoods, isSide } = require('../src/services/vision/dish-foods');

const all = [...Object.values(DISH_FOODS).flat(), ...SIDE_FOODS];
const menuOf = (names) => names.map((name, i) => ({ foodId: i + 1, name }));

test('a menu holding every classifier food misses none, whatever the case', () => {
  assert.deepEqual(missingDishFoods(menuOf(all)), []);
  assert.deepEqual(missingDishFoods(menuOf(all.map((n) => n.toUpperCase()))), []);
});

test('a renamed or hidden classifier food is named, in DISH_FOODS order', () => {
  const menu = menuOf(all.filter((n) => n !== 'Tinolang manok' && n !== 'Beef tapa').concat('Tinola (chicken)'));
  assert.deepEqual(missingDishFoods(menu), ['Tinolang manok', 'Beef tapa']);
});

test('an empty menu misses all 24 dish foods and every side food', () => {
  assert.deepEqual(missingDishFoods([]), all);
  assert.equal(Object.values(DISH_FOODS).flat().length, 24);
});

test('a side is a listed rice or egg, or a drink, condiment, bread or fresh side by its group', () => {
  assert.ok(isSide({ name: 'WHITE RICE', group: 'home' }));
  assert.ok(isSide({ name: 'Cola', group: 'drink' }));
  assert.ok(isSide({ name: 'Monay', group: 'bread_kakanin' }));
  assert.ok(!isSide({ name: 'Bistek tagalog', group: 'home' }));
  assert.ok(!isSide({ name: 'Ginisang ampalaya with egg', group: 'home' }), 'a dish with egg is no side');
});

test('a food of unknown type (a FatSecret copy) is never the AI\'s dish, so it counts as a side', () => {
  assert.ok(isSide({ name: 'Some FatSecret food', group: null }));
  assert.ok(isSide({ name: 'Some FatSecret food' }));
});
