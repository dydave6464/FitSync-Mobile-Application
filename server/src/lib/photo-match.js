'use strict';
const { estimateServings } = require('./photo-portion');

const MAX_CARDS = 8;
const MAX_ALTERNATIVES = 2;
const MAX_SERVINGS = 10;
/// A menu name as one line: the prompt lists one name per line, so line
/// breaks and tabs inside a name (a FatSecret copy is third-party text)
/// become spaces. The prompt and the matching below both use it.
const menuLine = (s) => String(s).replace(/[\r\n\t]+/g, ' ').trim();
const key = (s) => menuLine(s).toLowerCase();

/// The AI's items as the confirm screen's cards. [menu] is the list the AI
/// chose from. A name is matched to a menu food ignoring case -- "menu"
/// first, then "name" (the model sometimes puts the menu name only there);
/// one matching nothing is unlisted (once per name). Two items naming the
/// same food become one, servings added (at most 10), keeping the first's
/// confidence and alternatives. At most 8 cards in all, in the AI's order.
/// Alternatives are other menu foods: unknown names, the item's own food and
/// repeats are dropped, and at most two are kept.
function matchItems(rawItems, menu) {
  const byName = new Map(menu.map((f) => [key(f.name), f]));
  const lookup = (s) => (s ? byName.get(key(s)) : undefined);
  const items = [];
  const unlisted = [];
  const full = () => items.length + unlisted.length >= MAX_CARDS;

  for (const it of rawItems) {
    const food = lookup(it.menu) ?? lookup(it.name);
    if (!food) {
      if (unlisted.some((u) => key(u.name) === key(it.name)) || full()) continue;
      unlisted.push({ name: it.name, confidence: it.confidence });
      continue;
    }
    const servings = estimateServings(it, food.servingDesc);
    const same = items.find((x) => x.food.foodId === food.foodId);
    if (same) {
      same.servings = Math.min(MAX_SERVINGS, same.servings + servings);
      continue;
    }
    if (full()) continue;
    const alternatives = [];
    for (const name of it.alternatives) {
      const alt = lookup(name);
      if (!alt || alt.foodId === food.foodId || alternatives.some((a) => a.foodId === alt.foodId)) continue;
      alternatives.push(alt);
      if (alternatives.length === MAX_ALTERNATIVES) break;
    }
    items.push({ food, servings, confidence: it.confidence, alternatives });
  }
  return { items, unlisted };
}

module.exports = { matchItems, menuLine, MAX_CARDS };
