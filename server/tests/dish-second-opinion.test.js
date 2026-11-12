'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { secondOpinion } = require('../src/services/vision/dish-second-opinion');
const { DISH_FOODS } = require('../src/services/vision/dish-foods');
const { FOODS } = require('../src/db/seed-foods');

let nextId = 0;
const MENU = [
  'Sinigang na baboy', 'Sinigang na hipon', 'Tinolang manok', 'Red Filipino hotdog', 'Vigan longganisa',
  'Pork tocino', 'White rice', 'Garlic fried rice (sinangag)', 'Chicken adobo', 'Fried egg',
].map((name) => ({ foodId: ++nextId, name }));
const byName = new Map(MENU.map((f) => [f.name.toLowerCase(), f]));
const food = (name) => byName.get(name.toLowerCase());
const card = (name, alternatives = []) => ({ food: food(name), servings: 1.5, confidence: 0.8, alternatives: alternatives.map(food) });
const opinion = (dish, probability, extra = {}) => ({
  model: 'dish-lr-1-test', dishes: [{ dish, probability }], swapAt: 0.8, choiceAt: 0.5,
  classes: Object.keys(DISH_FOODS).sort(), ...extra,
});
const shown = (items) => items.map((it) => [it.food.name, it.alternatives.map((a) => a.name)]);

test('the 12 dishes point only to foods on the seed menu', () => {
  const menu = new Set(FOODS.map((f) => f.name));
  assert.equal(Object.keys(DISH_FOODS).length, 12);
  for (const [dish, names] of Object.entries(DISH_FOODS)) {
    for (const n of names) assert.ok(menu.has(n), `${dish}: ${n} is not a seed food`);
  }
});

test("a sure classifier swaps the main dish; the AI's pick becomes the first choice", () => {
  const items = [card('Tinolang manok', ['Chicken adobo']), card('White rice')];
  const out = secondOpinion(items, opinion('sinigang', 0.93), byName);
  assert.equal(out.outcome, 'swapped');
  assert.deepEqual(shown(out.items), [['Sinigang na baboy', ['Tinolang manok', 'Chicken adobo']], ['White rice', []]]);
  assert.equal(out.items[0].servings, 1.5, "the portion stays the AI's");
  assert.deepEqual(shown(items), [['Tinolang manok', ['Chicken adobo']], ['White rice', []]], 'the input is not changed');
});

test('a swap keeps the version the AI named anywhere in its answer', () => {
  const out = secondOpinion([card('Tinolang manok', ['Sinigang na hipon'])], opinion('sinigang', 0.9), byName);
  assert.deepEqual(shown(out.items), [['Sinigang na hipon', ['Tinolang manok']]]);
});

test('the main dish is the first card that is one of the 12, not simply the first card', () => {
  const items = [card('Garlic fried rice (sinangag)'), card('Red Filipino hotdog'), card('Fried egg')];
  const out = secondOpinion(items, opinion('longganisa', 0.95), byName);
  assert.equal(out.outcome, 'swapped');
  assert.deepEqual(out.items.map((it) => it.food.name), ['Garlic fried rice (sinangag)', 'Vigan longganisa', 'Fried egg']);
});

test("fairly sure adds the classifier's dish as the first choice and keeps the AI's pick", () => {
  const out = secondOpinion([card('Red Filipino hotdog', ['Chicken adobo', 'Fried egg'])], opinion('tocino', 0.6), byName);
  assert.equal(out.outcome, 'added choice');
  assert.deepEqual(shown(out.items), [['Red Filipino hotdog', ['Pork tocino', 'Chicken adobo']]]);
});

test('nothing changes when the classifier agrees, is unsure, or is already a choice', () => {
  const items = [card('Tinolang manok', ['Sinigang na baboy'])];
  assert.equal(secondOpinion(items, opinion('tinola', 0.99), byName).outcome, 'agreed');
  assert.equal(secondOpinion(items, opinion('tocino', 0.3), byName).outcome, 'skipped');
  const chip = secondOpinion(items, opinion('sinigang', 0.6), byName);
  assert.equal(chip.outcome, 'skipped');
  assert.equal(chip.items, items);
});

test('the classifier is ignored when no card is one of the 12', () => {
  const items = [card('Chicken adobo'), card('White rice')];
  const out = secondOpinion(items, opinion('tinola', 0.99), byName);
  assert.equal(out.outcome, 'skipped');
  assert.equal(out.items, items);
});

test('no swap onto a food that is already a card of its own', () => {
  const items = [card('Tinolang manok'), card('Sinigang na baboy')];
  assert.equal(secondOpinion(items, opinion('sinigang', 0.95), byName).outcome, 'skipped');
});

test('no swap onto a dish that is already a card of its own, in another version', () => {
  // The swap would pick the choice's Sinigang na baboy beside a Sinigang na hipon card.
  const items = [card('Tinolang manok', ['Sinigang na baboy']), card('Sinigang na hipon')];
  const out = secondOpinion(items, opinion('sinigang', 0.9), byName);
  assert.equal(out.outcome, 'skipped');
  assert.equal(out.items, items);
});

test("a dish the model was not trained on is never the main dish, so a right AI answer stays", () => {
  // Tocino dropped from training: the model can never answer tocino, so its
  // confident longganisa on a tocino plate is no disagreement to act on.
  const classes = Object.keys(DISH_FOODS).filter((d) => d !== 'tocino');
  const items = [card('Pork tocino')];
  const out = secondOpinion(items, opinion('longganisa', 0.92, { classes }), byName);
  assert.equal(out.outcome, 'skipped');
  assert.equal(out.items, items);
});

test('the main dish is the first card the model was trained on', () => {
  const classes = Object.keys(DISH_FOODS).filter((d) => d !== 'tocino');
  const items = [card('Pork tocino'), card('Red Filipino hotdog')];
  const out = secondOpinion(items, opinion('longganisa', 0.95, { classes }), byName);
  assert.equal(out.outcome, 'swapped');
  assert.deepEqual(out.items.map((it) => it.food.name), ['Pork tocino', 'Vigan longganisa']);
});

test("the classifier's dish must be one of its own classes", () => {
  const classes = Object.keys(DISH_FOODS).filter((d) => d !== 'sinigang');
  const items = [card('Tinolang manok')];
  assert.equal(secondOpinion(items, opinion('sinigang', 0.95, { classes }), byName).outcome, 'skipped');
});

test('a dish with no food on this menu, or one this server does not know, changes nothing', () => {
  const items = [card('Tinolang manok')];
  assert.equal(secondOpinion(items, opinion('bulalo', 0.95), byName).outcome, 'skipped');
  assert.equal(secondOpinion(items, opinion('adobo', 0.95), byName).outcome, 'skipped');
});

test('no opinion, or a malformed one, is unavailable and changes nothing', () => {
  const items = [card('Tinolang manok')];
  const bad = [
    null, {}, { dishes: [] }, opinion('sinigang', 1.5), opinion('sinigang', 0.9, { swapAt: 0.4, choiceAt: 0.6 }),
    opinion('sinigang', 0.9, { swapAt: undefined }), { ...opinion('sinigang', 0.9), dishes: [{ dish: 7, probability: 0.9 }] },
    opinion('sinigang', 0.9, { classes: undefined }), opinion('sinigang', 0.9, { classes: [] }),
    opinion('sinigang', 0.9, { classes: ['sinigang', 7] }), opinion('sinigang', 0.9, { classes: 'sinigang' }),
  ];
  for (const o of bad) {
    const out = secondOpinion(items, o, byName);
    assert.equal(out.outcome, 'unavailable', JSON.stringify(o));
    assert.equal(out.items, items);
  }
});

// Foods with their seed servings, for the portion tests below.
const SIZED = new Map([
  ['red filipino hotdog', { ...food('Red Filipino hotdog'), servingDesc: '1 piece (45 g), boiled or fried' }],
  ['pork tocino', { ...food('Pork tocino'), servingDesc: '1 serving (112 g), fried' }],
  ['vigan longganisa', { ...food('Vigan longganisa'), servingDesc: '2 links' }],
]);
const sized = (name, servings, alternatives = []) => ({
  food: SIZED.get(name.toLowerCase()), servings, confidence: 0.7, alternatives: alternatives.map((n) => SIZED.get(n.toLowerCase())),
});

test("a swap keeps the AI's amount, not its count, when the servings weigh differently", () => {
  // 2 hotdogs of 45 g = 90 g = 0.8 of a 112 g tocino serving -> 1 in halves.
  const out = secondOpinion([sized('Red Filipino hotdog', 2)], opinion('tocino', 0.9), SIZED);
  assert.equal(out.outcome, 'swapped');
  assert.equal(out.items[0].food.name, 'Pork tocino');
  assert.equal(out.items[0].servings, 1);
  assert.equal(out.items[0].confidence, 0.7, "the confidence stays the AI's");
});

test('a swap keeps the count when either serving gives no grams', () => {
  const out = secondOpinion([sized('Red Filipino hotdog', 2)], opinion('longganisa', 0.9), SIZED);
  assert.equal(out.outcome, 'swapped');
  assert.equal(out.items[0].servings, 2);
});

test('a swap stays within the servings range', () => {
  // 5 x 112 g = 560 g = 12.4 hotdogs -> the most a card holds.
  const out = secondOpinion([sized('Pork tocino', 5)], opinion('hotdog', 0.9), SIZED);
  assert.equal(out.items[0].food.name, 'Red Filipino hotdog');
  assert.equal(out.items[0].servings, 10);
});

test('adding a choice leaves the servings alone', () => {
  const out = secondOpinion([sized('Red Filipino hotdog', 2)], opinion('tocino', 0.6), SIZED);
  assert.equal(out.outcome, 'added choice');
  assert.equal(out.items[0].servings, 2);
});
