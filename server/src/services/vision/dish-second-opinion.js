'use strict';
const { DISH_FOODS, DISH_OF_NAME, isSide } = require('./dish-foods');
const { MAX_ALTERNATIVES } = require('../../lib/photo-match');
const { servingGrams, toHalf } = require('../../lib/photo-portion');

const dishOf = (food) => DISH_OF_NAME.get(String(food.name).toLowerCase());
const isProbability = (n) => typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= 1.01;

/// A /classify-dish answer this rule can act on. [classes] is every dish the
/// model was trained on: a dish dropped for too few photos is not among them.
function usable(opinion) {
  const top = Array.isArray(opinion?.dishes) ? opinion.dishes[0] : undefined;
  const { classes, outsideSwapAt } = opinion ?? {};
  return typeof top?.dish === 'string' && isProbability(top.probability)
    && isProbability(opinion.swapAt) && isProbability(opinion.choiceAt) && opinion.choiceAt <= opinion.swapAt
    // Round 2's very-sure bar is optional; when sent it must be a probability at or above swapAt.
    && (outsideSwapAt == null || (isProbability(outsideSwapAt) && outsideSwapAt >= opinion.swapAt))
    && Array.isArray(classes) && classes.length > 0 && classes.every((c) => typeof c === 'string');
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

/// [servings] of [from] as servings of [to], so the amount stays the same:
/// 2 hotdogs of 45 g are about 1 tocino serving of 112 g. Keeps the count
/// when either serving gives no grams.
function sameAmount(servings, from, to) {
  const was = servingGrams(from.servingDesc);
  const now = servingGrams(to.servingDesc);
  return was && now ? toHalf((servings * was) / now) : servings;
}

/// Puts [food] on the card at [at]: at or above [bar] it replaces the card's
/// food (the old one becomes the first choice, the servings keep the same
/// amount), below it [food] is added as the first choice unless it already is
/// one. [suffix] tells the log which rule acted ('' or ' outside').
function act(items, at, food, probability, bar, suffix) {
  const main = items[at];
  const replaced = (card) => items.map((it, i) => (i === at ? card : it));
  if (probability >= bar) {
    const alternatives = [main.food, ...main.alternatives.filter((f) => f.foodId !== food.foodId)]
      .slice(0, MAX_ALTERNATIVES);
    const servings = sameAmount(main.servings, main.food, food);
    return { items: replaced({ ...main, food, servings, alternatives }), outcome: `swapped${suffix}` };
  }
  if (main.alternatives.some((f) => f.foodId === food.foodId)) return { items, outcome: 'skipped' };
  const alternatives = [food, ...main.alternatives].slice(0, MAX_ALTERNATIVES);
  return { items: replaced({ ...main, alternatives }), outcome: `added choice${suffix}` };
}

/// Round 2 (spec 2026-11-12, section 3): the AI named none of the 12. The
/// AI's dish is its first card that is no side; a very sure classifier
/// (outsideSwapAt) replaces it, a fairly sure one (choiceAt) adds a choice.
/// Never adds or removes a card, so what counts toward the daily limit is
/// unchanged. A round-1 answer has no outsideSwapAt and changes nothing.
/// A card of the 12 the model was not trained on means the AI did name one
/// of the 12, so that answer stays as round 1 left it.
function outside(items, opinion, menuByName) {
  const skipped = { items, outcome: 'skipped' };
  if (items.some((it) => dishOf(it.food))) return skipped;
  const { dish, probability } = opinion.dishes[0];
  if (opinion.outsideSwapAt == null || !Object.hasOwn(DISH_FOODS, dish) || !opinion.classes.includes(dish)) {
    return skipped;
  }
  if (probability < opinion.choiceAt) return skipped;
  const at = items.findIndex((it) => !isSide(it.food));
  if (at === -1) return skipped;
  const food = foodFor(dish, items, menuByName);
  if (!food) return skipped;
  return act(items, at, food, probability, opinion.outsideSwapAt, ' outside');
}

/// The dish classifier's second opinion on the main dish (spec
/// 2026-11-05-food-classifier, section 3). [items] are matchItems' cards,
/// [opinion] the ML service's answer (null when it had none), [menuByName]
/// a lower-case menu name -> food map. Returns the cards to answer with and
/// one word for the log. Only the first card that is one of the 12 dishes
/// and one of the model's classes can change, and only to another of both:
/// when the AI named none of the 12, `outside` decides (round 2). A
/// dish dropped from training is never the main dish, or a right AI answer
/// would always look like a disagreement. The amount and confidence
/// stay the AI's: a swap rescales the servings to the new food's serving.
/// Never changes [items]; returns it as is when nothing changes.
function secondOpinion(items, opinion, menuByName) {
  if (!usable(opinion)) return { items, outcome: 'unavailable' };
  const known = new Set(opinion.classes);
  const at = items.findIndex((it) => known.has(dishOf(it.food)));
  if (at === -1) return outside(items, opinion, menuByName);
  const main = items[at];
  const { dish, probability } = opinion.dishes[0];
  if (!Object.hasOwn(DISH_FOODS, dish) || !known.has(dish)) return { items, outcome: 'skipped' };
  if (dish === dishOf(main.food)) return { items, outcome: 'agreed' };
  if (probability < opinion.choiceAt) return { items, outcome: 'skipped' };
  const food = foodFor(dish, items, menuByName);
  // Already a card of its own, in any version: a swap would show the dish twice.
  if (!food || items.some((it, i) => i !== at && dishOf(it.food) === dish)) {
    return { items, outcome: 'skipped' };
  }
  return act(items, at, food, probability, opinion.swapAt, '');
}

module.exports = { secondOpinion };
