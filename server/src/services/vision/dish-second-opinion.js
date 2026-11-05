'use strict';
const { DISH_FOODS, DISH_OF_NAME } = require('./dish-foods');
const { MAX_ALTERNATIVES } = require('../../lib/photo-match');

const dishOf = (food) => DISH_OF_NAME.get(String(food.name).toLowerCase());
const isProbability = (n) => typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= 1.01;

/// A /classify-dish answer this rule can act on.
function usable(opinion) {
  const top = Array.isArray(opinion?.dishes) ? opinion.dishes[0] : undefined;
  return typeof top?.dish === 'string' && isProbability(top.probability)
    && isProbability(opinion.swapAt) && isProbability(opinion.choiceAt) && opinion.choiceAt <= opinion.swapAt;
}

/// The menu food that stands for [dish]: one the AI already named (a card or
/// a choice), else the dish's default, else the first of its foods on the menu.
function foodFor(dish, items, menuByName) {
  const names = new Set(DISH_FOODS[dish].map((n) => n.toLowerCase()));
  for (const it of items) {
    const named = [it.food, ...it.alternatives].find((f) => names.has(String(f.name).toLowerCase()));
    if (named) return named;
  }
  for (const n of DISH_FOODS[dish]) {
    const f = menuByName.get(n.toLowerCase());
    if (f) return f;
  }
  return null;
}

/// The dish classifier's second opinion on the main dish (spec
/// 2026-11-05-food-classifier, section 3). [items] are matchItems' cards,
/// [opinion] the ML service's answer (null when it had none), [menuByName]
/// a lower-case menu name -> food map. Returns the cards to answer with and
/// one word for the log. Only the first card that is one of the 12 dishes
/// can change, and only to another of the 12: the classifier knows nothing
/// else, so for any other food it is ignored. Portion and confidence stay
/// the AI's. Never changes [items]; returns it as is when nothing changes.
function secondOpinion(items, opinion, menuByName) {
  if (!usable(opinion)) return { items, outcome: 'unavailable' };
  const at = items.findIndex((it) => dishOf(it.food));
  if (at === -1) return { items, outcome: 'skipped' };
  const main = items[at];
  const { dish, probability } = opinion.dishes[0];
  if (!Object.hasOwn(DISH_FOODS, dish)) return { items, outcome: 'skipped' };
  if (dish === dishOf(main.food)) return { items, outcome: 'agreed' };
  if (probability < opinion.choiceAt) return { items, outcome: 'skipped' };
  const food = foodFor(dish, items, menuByName);
  // Already a card of its own: a swap would show the same food twice.
  if (!food || items.some((it, i) => i !== at && it.food.foodId === food.foodId)) {
    return { items, outcome: 'skipped' };
  }
  const replaced = (card) => items.map((it, i) => (i === at ? card : it));
  if (probability >= opinion.swapAt) {
    const alternatives = [main.food, ...main.alternatives.filter((f) => f.foodId !== food.foodId)]
      .slice(0, MAX_ALTERNATIVES);
    return { items: replaced({ ...main, food, alternatives }), outcome: 'swapped' };
  }
  if (main.alternatives.some((f) => f.foodId === food.foodId)) return { items, outcome: 'skipped' };
  const alternatives = [food, ...main.alternatives].slice(0, MAX_ALTERNATIVES);
  return { items: replaced({ ...main, alternatives }), outcome: 'added choice' };
}

module.exports = { secondOpinion };
