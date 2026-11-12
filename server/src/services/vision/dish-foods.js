'use strict';

/// The dish classifier's 12 dishes and the menu foods each stands for, the
/// default first (spec 2026-11-05-food-classifier, section 1). The
/// classifier names the dish; which of its foods is shown comes from the
/// vision AI when it named one, else the default.
const DISH_FOODS = Object.freeze({
  sinigang: ['Sinigang na baboy', 'Sinigang na hipon', 'Sinigang na bangus (milkfish sour soup)'],
  tinola: ['Tinolang manok'],
  nilaga: ['Nilagang baka', 'Nilagang baboy (boiled pork soup)'],
  bulalo: ['Bulalo'],
  palabok: ['Pancit palabok', 'Mang Inasal Palabok'],
  bihon: ['Pancit bihon'],
  canton: ['Pancit canton', 'Lucky Me Pancit Canton (original)', 'Chowking Pancit Canton'],
  spaghetti: ['Spaghetti with meat sauce', 'Jollibee Jolly Spaghetti', "McDonald's PH McSpaghetti", 'Greenwich Spaghetti'],
  longganisa: ['Vigan longganisa', 'Lucban longganisa', 'Longganisa hamonado (sweet)'],
  hotdog: ['Red Filipino hotdog', 'Hotdog on a stick (grilled)'],
  tocino: ['Pork tocino'],
  tapa: ['Beef tapa'],
});

/// A food's lower-case name -> its dish.
const DISH_OF_NAME = new Map(
  Object.entries(DISH_FOODS).flatMap(([dish, names]) => names.map((n) => [n.toLowerCase(), dish])),
);

/// The DISH_FOODS names [menuFoods] lacks, ignoring case, in DISH_FOODS
/// order. The classifier finds its dishes by these exact names, so an
/// admin's rename or Hide quietly stops it acting for that food.
function missingDishFoods(menuFoods) {
  const onMenu = new Set(menuFoods.map((f) => String(f.name).toLowerCase()));
  return Object.values(DISH_FOODS).flat().filter((n) => !onMenu.has(n.toLowerCase()));
}

module.exports = { DISH_FOODS, DISH_OF_NAME, missingDishFoods };
