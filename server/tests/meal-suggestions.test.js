'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { pickSuggestions, dayNumber, asRiceFood } = require('../src/lib/meal-suggestions');

const RICE = {
  foodId: 1, name: 'White rice', servingDesc: '1 cup (160 g)', kcal: 206, proteinG: 3.4, carbsG: 47.5, fatG: 0.3,
};

/// A suggested food. Lunch and dinner with rice unless told otherwise.
const dish = (foodId, name, kcal, proteinG, {
  meals = ['lunch', 'dinner'], withRice = true, carbsG = 10, fatG = 10, servingDesc = '1 serving',
} = {}) => ({
  foodId, name, servingDesc, kcal, proteinG, carbsG, fatG, meals, withRice,
});

const TARGET = { kcal: 2000, proteinG: 100 };
const NOTHING = { kcal: 0, proteinG: 0 };

const pick = (over = {}) => pickSuggestions({
  meal: 'lunch', date: '2026-11-09', target: TARGET, totals: NOTHING, entries: [], pool: [], rice: RICE, ...over,
});
const names = (result) => result.suggestions.map((s) => s.food.name);
const share = (over) => pick({ pool: [dish(5, 'Tinolang manok', 260, 26)], ...over }).share;

test('a main meal shares what is left with the empty main meals still to come', () => {
  // Nothing logged: breakfast shares with lunch and dinner, lunch with dinner.
  assert.deepEqual(share({ meal: 'breakfast' }), { kcal: 667, proteinG: 33.3 });
  assert.deepEqual(share({ meal: 'lunch' }), { kcal: 1000, proteinG: 50 });
  assert.deepEqual(share({ meal: 'dinner' }), { kcal: 2000, proteinG: 100 });
  // Lunch already has food: breakfast now shares with dinner only.
  const lunchLogged = [{ mealType: 'lunch', foodId: 99 }];
  assert.deepEqual(share({ meal: 'breakfast', entries: lunchLogged }), { kcal: 1000, proteinG: 50 });
  // This meal always counts, even with food logged to it.
  assert.deepEqual(share({ meal: 'lunch', entries: lunchLogged }), { kcal: 1000, proteinG: 50 });
  // A snack logged earlier is no main meal.
  assert.deepEqual(share({ meal: 'lunch', entries: [{ mealType: 'snack', foodId: 99 }] }), { kcal: 1000, proteinG: 50 });
});

test('what is left is the target less today so far, protein never below 0', () => {
  assert.deepEqual(share({ meal: 'dinner', totals: { kcal: 1400, proteinG: 60 } }), { kcal: 600, proteinG: 40 });
  assert.deepEqual(share({ meal: 'dinner', totals: { kcal: 1400, proteinG: 130 } }), { kcal: 600, proteinG: 0 });
});

test('a snack is at most 250 kcal and 10 g protein, or what is left', () => {
  const snack = (totals) => pick({
    meal: 'snack', totals, pool: [dish(5, 'Hard-boiled egg', 78, 6.3, { meals: ['snack'], withRice: false })],
  }).share;
  assert.deepEqual(snack(NOTHING), { kcal: 250, proteinG: 10 });
  assert.deepEqual(snack({ kcal: 1820, proteinG: 96 }), { kcal: 180, proteinG: 4 });
});

test('rice goes with a main meal only, and only on a dish served with it', () => {
  const pool = [
    dish(5, 'Tinolang manok', 260, 26, { meals: ['lunch', 'snack'] }),
    dish(6, 'Tapsilog', 650, 35, { meals: ['lunch'], withRice: false }),
  ];
  const lunch = pick({ pool });
  const byName = Object.fromEntries(lunch.suggestions.map((s) => [s.food.name, s]));
  assert.equal(byName['Tinolang manok'].rice.foodId, RICE.foodId);
  assert.equal(byName.Tapsilog.rice, null);
  const snack = pick({ meal: 'snack', pool });
  assert.deepEqual(snack.suggestions.map((s) => [s.food.name, s.rice]), [['Tinolang manok', null]]);
});

test('a plate is the dish and the rice added up, as the app shows it', () => {
  const tinola = dish(5, 'Tinolang manok', 260, 26, { carbsG: 10, fatG: 12, servingDesc: '1 bowl (350 g)' });
  assert.deepEqual(pick({ pool: [tinola] }).suggestions, [{
    food: {
      foodId: 5, name: 'Tinolang manok', servingDesc: '1 bowl (350 g)', kcal: 260, proteinG: 26, carbsG: 10, fatG: 12,
    },
    rice: {
      foodId: 1, name: 'White rice', servingDesc: '1 cup (160 g)', servings: 1, kcal: 206, proteinG: 3.4, carbsG: 47.5, fatG: 0.3,
    },
    total: { kcal: 466, proteinG: 29.4, carbsG: 57.5, fatG: 12.3 },
    servedWithRice: true,
    highProtein: false,
  }]);
});

test('with no rice in the list, a plate is the dish alone', () => {
  const result = pick({ rice: null, pool: [dish(5, 'Tinolang manok', 260, 26)] });
  assert.equal(result.suggestions[0].rice, null);
  assert.equal(result.suggestions[0].total.kcal, 260);
});

test('plates over what is left are dropped, and short of three come back without rice', () => {
  // 400 kcal left; lunch shares it with dinner: 200 kcal and 50 g.
  const result = pick({
    totals: { kcal: 1600, proteinG: 0 },
    pool: [
      dish(5, 'A', 150, 20), // 356 with rice: fits
      dish(6, 'B', 250, 15), // 456 with rice: over; 250 alone fits
      dish(7, 'C', 450, 30), // over with rice and alone
      dish(8, 'D', 180, 10, { withRice: false }), // 180: fits
    ],
  });
  assert.deepEqual(result.share, { kcal: 200, proteinG: 50 });
  // D 0.10 - 0.10 = 0; B alone 0.25 - 0.15 = 0.10; A + rice 0.78 - 0.234 = 0.55.
  assert.deepEqual(result.suggestions.map((s) => [s.food.name, s.rice && s.rice.foodId]), [
    ['D', null], ['B', null], ['A', 1],
  ]);
});

test('with three plates that fit, none comes back without rice', () => {
  const result = pick({
    totals: { kcal: 1600, proteinG: 0 },
    pool: [dish(5, 'A', 150, 20), dish(6, 'B', 250, 15), dish(7, 'E', 100, 5), dish(8, 'F', 120, 8)],
  });
  // B alone (0.10) would beat all three, but three plates with rice fit.
  assert.deepEqual(result.suggestions.map((s) => [s.food.name, s.rice && s.rice.foodId]), [
    ['E', 1], ['F', 1], ['A', 1],
  ]);
});

test('ranks by closeness to the share, less a bonus for protein', () => {
  // Dinner with 600 kcal and 40 g left: the share is all of it.
  const result = pick({
    meal: 'dinner',
    rice: null,
    totals: { kcal: 1400, proteinG: 60 },
    pool: [
      dish(5, 'P', 600, 0), //    0     - 0     =  0
      dish(6, 'Q', 500, 40), //   0.167 - 0.5   = -0.33
      dish(7, 'R', 300, 20), //   0.5   - 0.25  =  0.25
      dish(8, 'S', 580, 8), //    0.033 - 0.1   = -0.07
    ],
  });
  // P matches the calories exactly, yet Q and S give more protein.
  assert.deepEqual(names(result), ['Q', 'S', 'P', 'R']);
});

test('the protein bonus stops at the share', () => {
  // 40 g and 80 g both meet a 40 g share: equal scores, so the day decides.
  const result = pick({
    meal: 'dinner',
    rice: null,
    totals: { kcal: 1400, proteinG: 60 },
    pool: [dish(10, 'Q40', 500, 40), dish(906, 'Q80', 500, 80), dish(7, 'R', 300, 20)],
  });
  assert.deepEqual(names(result), ['Q40', 'Q80', 'R']);
});

test('no protein left: no protein term, closeness alone', () => {
  const result = pick({
    meal: 'dinner',
    rice: null,
    totals: { kcal: 1400, proteinG: 100 },
    pool: [dish(5, 'U', 550, 50), dish(6, 'V', 600, 0)],
  });
  assert.equal(result.share.proteinG, 0);
  assert.deepEqual(names(result), ['V', 'U']);
});

test('equal scores take turns with the date', () => {
  // Foods 10 and 906, same numbers. On 2026-11-09 food 906's turn number is
  // 996 and food 10's 139; the next day 906 wraps to 0 and leads.
  assert.equal(dayNumber('2026-11-09'), 20766);
  const pool = [dish(10, 'Ten', 300, 20), dish(906, 'Nine-oh-six', 300, 20)];
  assert.deepEqual(names(pick({ date: '2026-11-09', pool })), ['Ten', 'Nine-oh-six']);
  assert.deepEqual(names(pick({ date: '2026-11-10', pool })), ['Nine-oh-six', 'Ten']);
});

test('a dish logged today, at any meal, is not suggested again', () => {
  const pool = [dish(5, 'Tinolang manok', 260, 26), dish(6, 'Grilled bangus', 206, 35.1)];
  const result = pick({ pool, entries: [{ mealType: 'breakfast', foodId: 5 }, { mealType: 'snack', foodId: null }] });
  assert.deepEqual(names(result), ['Grilled bangus']);
});

test('only the meal asked for: a breakfast dish is not a lunch', () => {
  const pool = [dish(5, 'Tortang talong', 180, 9, { meals: ['breakfast'] }), dish(6, 'Pinakbet', 150, 6)];
  assert.deepEqual(names(pick({ pool })), ['Pinakbet']);
});

test('no target: the most protein for the calories first, nothing dropped for size', () => {
  const result = pick({
    target: null,
    pool: [
      dish(5, 'Tinolang manok', 260, 26), //  466 kcal, 29.4 g: 0.25
      dish(6, 'Grilled bangus', 206, 35.1), // 412 kcal, 38.5 g: 0.37
      dish(7, 'Pinakbet', 150, 6), //          356 kcal,  9.4 g: 0.11
      dish(8, 'Lechon belly', 1500, 100), //  1706 kcal, 103.4 g: 0.24
      dish(9, 'Hard-boiled egg', 78, 6.3, { meals: ['snack'], withRice: false }),
    ],
  });
  assert.equal(result.state, 'no_target');
  assert.equal(result.share, null);
  assert.deepEqual(names(result), ['Grilled bangus', 'Tinolang manok', 'Lechon belly', 'Pinakbet']);
  assert.equal(result.suggestions[0].rice.foodId, RICE.foodId);
});

test('under 100 kcal left: light snacks, most protein first, never with rice', () => {
  const pool = [
    dish(5, 'Hard-boiled egg', 78, 6.3, { meals: ['snack'], withRice: false }),
    dish(6, 'Lakatan banana', 89, 1.1, { meals: ['snack'], withRice: false }),
    dish(7, 'Papaya fresh fruit', 62, 0.7, { meals: ['snack'], withRice: false }),
    dish(8, 'Pinya (pineapple)', 91, 0.7, { meals: ['snack'], withRice: false }),
    dish(9, 'Carabao mango, ripe', 140, 1.2, { meals: ['snack'], withRice: false }),
    dish(10, 'Tinolang manok', 260, 26),
    dish(11, 'Light breakfast', 90, 9, { meals: ['breakfast'] }),
  ];
  const result = pick({ meal: 'lunch', totals: { kcal: 1901, proteinG: 80 }, pool });
  assert.equal(result.state, 'reached');
  assert.equal(result.share, null);
  // Papaya before pineapple: the same protein, fewer calories.
  assert.deepEqual(names(result), ['Hard-boiled egg', 'Lakatan banana', 'Papaya fresh fruit', 'Pinya (pineapple)']);
  assert.ok(result.suggestions.every((s) => s.rice === null));
  // Exactly 100 kcal left still fits.
  assert.equal(pick({ totals: { kcal: 1900, proteinG: 80 }, pool }).state, 'fits');
});

test('high protein is 30% of the calories or more', () => {
  const snack = (proteinG) => pick({
    meal: 'snack', pool: [dish(5, 'X', 200, proteinG, { meals: ['snack'], withRice: false })],
  }).suggestions[0].highProtein;
  assert.equal(snack(15), true); //    60 / 200 = 0.30
  assert.equal(snack(14.9), false); // 59.6 / 200
});

test('at most nine, fewer when fewer qualify, none from an empty list', () => {
  const pool = Array.from({ length: 11 }, (_, i) => dish(i + 10, `Dish ${i}`, 200 + i, 20));
  assert.equal(pick({ pool }).suggestions.length, 9);
  assert.equal(pick({ pool: pool.slice(0, 2) }).suggestions.length, 2);
  assert.deepEqual(pick({ pool: [] }), { state: 'fits', share: { kcal: 1000, proteinG: 50 }, suggestions: [] });
});

/// Rice with round numbers, so scaled figures compare exactly.
const ROUND_RICE = {
  foodId: 1, name: 'White rice', servingDesc: '1 cup (160 g)', kcal: 200, proteinG: 4, carbsG: 40, fatG: 0.4,
};
const TINOLA = dish(5, 'Tinolang manok', 260, 26, { carbsG: 10, fatG: 12, servingDesc: '1 bowl (350 g)' });

test("rice is the user's usual cups: its numbers scaled, its servings said", () => {
  const plateAt = (riceCups) => pick({ pool: [TINOLA], rice: ROUND_RICE, riceCups }).suggestions[0];
  assert.deepEqual(plateAt(1.5).rice, {
    foodId: 1, name: 'White rice', servingDesc: '1 cup (160 g)', servings: 1.5, kcal: 300, proteinG: 6, carbsG: 60, fatG: 0.6,
  });
  assert.deepEqual(plateAt(1.5).total, { kcal: 560, proteinG: 32, carbsG: 70, fatG: 12.6 });
  assert.deepEqual(plateAt(0.5).total, { kcal: 360, proteinG: 28, carbsG: 30, fatG: 12.2 });
  assert.deepEqual(plateAt(2).total, { kcal: 660, proteinG: 34, carbsG: 90, fatG: 12.8 });
  assert.equal(plateAt(2).rice.servings, 2);
});

test('no rice as the usual: the dish alone, still marked as served with rice', () => {
  const [plate] = pick({ pool: [TINOLA], rice: ROUND_RICE, riceCups: 0 }).suggestions;
  assert.equal(plate.rice, null);
  assert.equal(plate.total.kcal, 260);
  assert.equal(plate.servedWithRice, true);
});

test('served with rice: a main meal, a dish served with it, and rice in the list', () => {
  const pool = [
    dish(5, 'Tinolang manok', 260, 26, { meals: ['lunch', 'snack'] }),
    dish(6, 'Tapsilog', 650, 35, { meals: ['lunch'], withRice: false }),
  ];
  const served = (over) => Object.fromEntries(pick({ pool, ...over }).suggestions.map((s) => [s.food.name, s.servedWithRice]));
  assert.deepEqual(served({}), { 'Tinolang manok': true, Tapsilog: false });
  assert.deepEqual(served({ meal: 'snack' }), { 'Tinolang manok': false });
  assert.deepEqual(served({ rice: null }), { 'Tinolang manok': false, Tapsilog: false });
});

test('a dish that comes back without its rice is still served with rice', () => {
  // As 'plates over what is left are dropped': B fits only without rice.
  const result = pick({
    totals: { kcal: 1600, proteinG: 0 },
    pool: [dish(5, 'A', 150, 20), dish(6, 'B', 250, 15), dish(8, 'D', 180, 10, { withRice: false })],
  });
  const byName = Object.fromEntries(result.suggestions.map((s) => [s.food.name, s]));
  assert.equal(byName.B.rice, null);
  assert.equal(byName.B.servedWithRice, true);
  assert.equal(byName.D.servedWithRice, false);
});

test("a dish eaten yesterday comes after every other, in each state, but still comes", () => {
  const yesterday = [{ foodId: 5 }, { foodId: null }];
  // fits: P would lead (it matches the share), but it was yesterday's.
  const fits = pick({
    meal: 'dinner', rice: null, totals: { kcal: 1400, proteinG: 60 }, yesterday,
    pool: [dish(5, 'P', 600, 40), dish(6, 'Q', 500, 30), dish(7, 'R', 300, 20)],
  });
  assert.deepEqual(names(fits), ['Q', 'R', 'P']);
  // no target: the most protein first, yesterday's last.
  const noTarget = pick({
    target: null, rice: null, yesterday, pool: [dish(5, 'Bangus', 206, 35), dish(6, 'Pinakbet', 150, 6)],
  });
  assert.deepEqual(names(noTarget), ['Pinakbet', 'Bangus']);
  // reached: the light snacks, yesterday's last.
  const snack = (id, name, kcal, proteinG) => dish(id, name, kcal, proteinG, { meals: ['snack'], withRice: false });
  const reached = pick({
    totals: { kcal: 1950, proteinG: 80 }, yesterday,
    pool: [snack(5, 'Egg', 78, 6.3), snack(6, 'Banana', 89, 1.1)],
  });
  assert.deepEqual(names(reached), ['Banana', 'Egg']);
  // The only dish there is still comes.
  assert.deepEqual(names(pick({ rice: null, yesterday, pool: [dish(5, 'P', 300, 20)] })), ['P']);
});

test("today's dishes are still skipped, yesterday's only moved", () => {
  const pool = [dish(5, 'A', 300, 20), dish(6, 'B', 300, 20)];
  const result = pick({ rice: null, pool, entries: [{ mealType: 'breakfast', foodId: 5 }], yesterday: [{ foodId: 6 }] });
  assert.deepEqual(names(result), ['B']);
});

test('White rice per cup, as the response gives it', () => {
  assert.deepEqual(asRiceFood(RICE), {
    foodId: 1, name: 'White rice', servingDesc: '1 cup (160 g)', kcal: 206, proteinG: 3.4, carbsG: 47.5, fatG: 0.3,
  });
  assert.equal(asRiceFood(null), null);
});
