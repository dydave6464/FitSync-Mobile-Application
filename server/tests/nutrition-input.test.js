'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { checkManual, checkClientId, basisId, perServingOf } = require('../src/lib/nutrition-input');

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

test('a basis id is absent (null) or a positive integer; anything else is a 400 on that field', () => {
  assert.equal(basisId({}, 'basedOnFoodId'), null);
  assert.equal(basisId({ basedOnFoodId: null }, 'basedOnFoodId'), null);
  assert.equal(basisId({ basedOnEntryId: 21 }, 'basedOnEntryId'), 21);
  for (const bad of ['21', 0, -1, 1.5, true, {}]) {
    assert.equal(fieldOf(() => basisId({ basedOnFoodId: bad }, 'basedOnFoodId')), 'basedOnFoodId', JSON.stringify(bad));
    assert.equal(fieldOf(() => basisId({ basedOnEntryId: bad }, 'basedOnEntryId')), 'basedOnEntryId', JSON.stringify(bad));
  }
});

test("a stored entry's per-serving numbers divide each total by its servings; unknown stays unknown", () => {
  assert.deepEqual(perServingOf({
    servings: 2, kcal: 258, proteinG: 2.2, carbsG: 21.2, fatG: 0, fiberG: null, sugarG: 3, sodiumMg: 80,
  }), { kcal: 129, proteinG: 1.1, carbsG: 10.6, fatG: 0, fiberG: null, sugarG: 1.5, sodiumMg: 40 });
});

test('a clientId is absent (null) or a v4 UUID, kept lower-case; anything else is a 400 on clientId', () => {
  assert.equal(checkClientId(undefined), null);
  assert.equal(checkClientId(null), null);
  assert.equal(checkClientId('3f1c2b9e-8d4a-4c1e-9b7a-2e5d6f708192'), '3f1c2b9e-8d4a-4c1e-9b7a-2e5d6f708192');
  assert.equal(checkClientId('3F1C2B9E-8D4A-4C1E-9B7A-2E5D6F708192'), '3f1c2b9e-8d4a-4c1e-9b7a-2e5d6f708192');
  for (const bad of [
    'not-a-uuid', 123, '', true, {},
    '3f1c2b9e-8d4a-1c1e-9b7a-2e5d6f708192', // version 1, not 4
    '3f1c2b9e-8d4a-4c1e-7b7a-2e5d6f708192', // not the RFC variant
    ' 3f1c2b9e-8d4a-4c1e-9b7a-2e5d6f708192', '3f1c2b9e8d4a4c1e9b7a2e5d6f708192',
  ]) {
    assert.equal(fieldOf(() => checkClientId(bad)), 'clientId', JSON.stringify(bad));
  }
  try { checkClientId('x'); } catch (e) {
    assert.equal(e.code, 'INVALID_NUTRITION_FIELD');
    assert.equal(e.message, 'clientId must be a UUID.');
  }
});
