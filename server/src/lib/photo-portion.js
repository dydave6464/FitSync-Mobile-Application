'use strict';

const MIN_SERVINGS = 0.5;
const MAX_SERVINGS = 10;

/// Household units, singular and lower case, so the AI's "pcs" meets a
/// serving's "piece".
const UNIT_ALIASES = {
  pc: 'piece', pcs: 'piece', pieces: 'piece', cups: 'cup', slices: 'slice', glasses: 'glass',
  bowls: 'bowl', skewers: 'skewer', sticks: 'stick', plates: 'plate', packs: 'pack', sachets: 'sachet',
  bottles: 'bottle', cans: 'can', tablespoon: 'tbsp', tablespoons: 'tbsp', tbsps: 'tbsp',
  teaspoon: 'tsp', teaspoons: 'tsp', tsps: 'tsp',
};

function unitKey(word) {
  const w = String(word).toLowerCase().replace(/[^a-z]/g, '');
  if (UNIT_ALIASES[w]) return UNIT_ALIASES[w];
  if (w.endsWith('ss')) return w;
  return w.endsWith('s') ? w.slice(0, -1) : w;
}

/// The grams one serving weighs (ml taken as grams), from the last "(N g)",
/// "(~N g)" or "(N ml)" in its text; null when it gives none.
function servingGrams(servingDesc) {
  if (typeof servingDesc !== 'string') return null;
  const all = [...servingDesc.matchAll(/\(\s*~?\s*(\d+(?:\.\d+)?)\s*(?:g|ml)\s*\)/gi)];
  if (all.length === 0) return null;
  const n = Number(all.at(-1)[1]);
  return n > 0 ? n : null;
}

/// "2 pieces" -> { count: 2, unit: 'piece' }; "1/2 cup" -> { count: 0.5,
/// unit: 'cup' }; "piece" -> count 1. Null when it doesn't start that way.
function leadingUnit(servingDesc) {
  if (typeof servingDesc !== 'string') return null;
  const m = servingDesc.match(/^\s*(?:(\d+)\/(\d+)|(\d+(?:\.\d+)?))?\s*([A-Za-z]+)/);
  if (!m) return null;
  const count = m[1] ? Number(m[1]) / Number(m[2]) : m[3] ? Number(m[3]) : 1;
  return count > 0 ? { count, unit: unitKey(m[4]) } : null;
}

const toHalf = (s) => Math.min(MAX_SERVINGS, Math.max(MIN_SERVINGS, Math.round(s * 2) / 2));

/// How many of the food's servings the AI's portion is: its grams over the
/// serving's grams; else its quantity over the serving's count when the
/// units match ("3 pieces" of "1 piece"); else 1. Always 0.5 to 10, in
/// halves -- the confirm screen's stepper fixes the rest.
function estimateServings({ grams, quantity, unit }, servingDesc) {
  const per = servingGrams(servingDesc);
  if (per && grams > 0) return toHalf(grams / per);
  const lead = leadingUnit(servingDesc);
  if (lead && quantity > 0 && unit && unitKey(unit) === lead.unit) return toHalf(quantity / lead.count);
  return 1;
}

module.exports = { servingGrams, estimateServings };
