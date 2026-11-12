'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { DISH_FOODS, missingDishFoods } = require('../src/services/vision/dish-foods');

const all = Object.values(DISH_FOODS).flat();
const menuOf = (names) => names.map((name, i) => ({ foodId: i + 1, name }));

test('a menu holding every classifier food misses none, whatever the case', () => {
  assert.deepEqual(missingDishFoods(menuOf(all)), []);
  assert.deepEqual(missingDishFoods(menuOf(all.map((n) => n.toUpperCase()))), []);
});

test('a renamed or hidden classifier food is named, in DISH_FOODS order', () => {
  const menu = menuOf(all.filter((n) => n !== 'Tinolang manok' && n !== 'Beef tapa').concat('Tinola (chicken)'));
  assert.deepEqual(missingDishFoods(menu), ['Tinolang manok', 'Beef tapa']);
});

test('an empty menu misses all 24', () => {
  assert.deepEqual(missingDishFoods([]), all);
  assert.equal(all.length, 24);
});
