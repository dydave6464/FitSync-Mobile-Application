'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { checkManual } = require('../src/lib/nutrition-input');

// A listed beer: its kcal includes alcohol, which 4-4-9 can't see.
const BEER = { kcal: 129, proteinG: 1.1, carbsG: 10.6, fatG: 0 };
// A listed spirit: all of its kcal is alcohol.
const SPIRIT = { kcal: 97, proteinG: 0, carbsG: 0, fatG: 0 };

const fieldOf = (fn) => {
  try { fn(); } catch (e) { return e.details && e.details[0].field; }
  return undefined;
};

test('without a listed food, kcal is 4-4-9 and 0/0/0 is refused', () => {
  assert.equal(checkManual({ name: 'Turon', proteinG: 2, carbsG: 34, fatG: 6 }).kcal, 198);
  assert.equal(fieldOf(() => checkManual({ name: 'Water', proteinG: 0, carbsG: 0, fatG: 0 })), 'food');
});

test("unchanged protein, carbs and fat keep the listed food's kcal", () => {
  const m = checkManual({ name: 'Beer', proteinG: 1.1, carbsG: 10.6, fatG: 0, sodiumMg: 30 }, { basedOn: BEER });
  assert.equal(m.kcal, 129);
  assert.equal(m.sodiumMg, 30);
});

test('equal after the same 2-dp rounding counts as unchanged', () => {
  const listed = { kcal: 129, proteinG: 1.104, carbsG: 10.6, fatG: 0 };
  assert.equal(checkManual({ name: 'Beer', proteinG: 1.1, carbsG: 10.6, fatG: 0 }, { basedOn: listed }).kcal, 129);
});

test('0/0/0 unchanged from a listed food with kcal is allowed, at its kcal', () => {
  assert.equal(checkManual({ name: 'Gin', proteinG: 0, carbsG: 0, fatG: 0 }, { basedOn: SPIRIT }).kcal, 97);
});

test('0/0/0 unchanged from a listed food with no kcal is still refused', () => {
  const water = { kcal: 0, proteinG: 0, carbsG: 0, fatG: 0 };
  assert.equal(fieldOf(() => checkManual({ name: 'Water', proteinG: 0, carbsG: 0, fatG: 0 }, { basedOn: water })), 'food');
});

test('changed carbs recompute kcal from 4-4-9', () => {
  const m = checkManual({ name: 'Beer', proteinG: 1.1, carbsG: 5, fatG: 0 }, { basedOn: BEER });
  assert.equal(m.kcal, 24); // round(4.4 + 20)
});

test('macros changed to 0/0/0 are refused, whatever the listed kcal', () => {
  assert.equal(fieldOf(() => checkManual({ name: 'Beer', proteinG: 0, carbsG: 0, fatG: 0 }, { basedOn: BEER })), 'food');
});
