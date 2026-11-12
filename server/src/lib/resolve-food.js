'use strict';
const AppError = require('./app-error');
const { invalid, checkManual, basisId, perServingOf } = require('./nutrition-input');
const { findFood, upsertFatsecretFood } = require('../db/foods');
const { getStoredEntry } = require('../db/nutrition');

/// One serving of the food a log request names, ready to multiply:
/// { foodId, customName, servingDesc, kcal, proteinG, carbsG, fatG, fiberG,
/// sugarG, sodiumMg, manual }. [food] is the request's `food` object:
/// { source: 'local', id } | { source: 'fatsecret', externalId } |
/// { source: 'manual', name, …, basedOnFoodId?, basedOnEntryId? }, where
/// basedOnEntryId is one of [userId]'s logged entries (from Recents). A
/// FatSecret food is fetched and copied into foods; that copy stays even if the
/// caller's own write then fails -- it is only a cache of FatSecret's numbers.
async function resolveFood({ pool, fatsecret, logger }, food, userId) {
  const f = food || {};
  if (f.source === 'local') {
    const found = Number.isInteger(f.id) ? await findFood(pool, f.id) : null;
    if (!found) throw AppError.notFound('FOOD_NOT_FOUND', 'That food is not in the list.');
    // The serving text is stored on the entry, not read through the foods
    // row, so a later seed re-run can't relabel what was already logged.
    return { ...found, customName: null, manual: false };
  }
  if (f.source === 'fatsecret') {
    if (typeof f.externalId !== 'string' || f.externalId === '' || f.externalId.length > 64) {
      throw invalid('food', 'externalId is required for a FatSecret food.');
    }
    let fetched;
    try {
      fetched = fatsecret ? await fatsecret.get(f.externalId) : undefined;
    } catch (e) {
      // The 502 below is deliberately generic -- "FatSecret is down" --
      // but that must not also be true of a real bug on our side (a bad
      // externalId we built, a client misuse). Log the message only:
      // never the whole error object (stack may embed request internals)
      // or anything from the request itself.
      if (logger) logger.warn({ externalId: f.externalId, err: e.message }, 'FatSecret food lookup failed');
      fetched = undefined;
    }
    if (fetched === undefined) {
      throw new AppError(502, 'FATSECRET_UNAVAILABLE', "Couldn't reach FatSecret. Try again, or add the food manually.");
    }
    if (fetched === null) throw AppError.notFound('FOOD_NOT_FOUND', 'FatSecret has no such food.');
    const foodId = await upsertFatsecretFood(pool, fetched);
    // Stored on the entry for the same reason (the next log of this food
    // refreshes the copy), and capped like it: meal_logs.serving_desc is
    // VARCHAR(255) too.
    const servingDesc = fetched.servingDesc == null ? null : String(fetched.servingDesc).slice(0, 255);
    return { ...fetched, foodId, customName: null, servingDesc, manual: false };
  }
  if (f.source === 'manual') {
    // What the user started from, if anything: its kcal is kept when they left
    // protein, carbs and fat alone. One of their own logged entries comes
    // first -- it is what they actually logged -- then a listed food. An id
    // that isn't one (or is someone else's entry) is no basis, not a 404, so
    // it says nothing about what exists.
    const foodId = basisId(f, 'basedOnFoodId');
    const entryId = basisId(f, 'basedOnEntryId');
    const entry = entryId === null ? null : await getStoredEntry(pool, userId, entryId);
    const basedOn = entry ? perServingOf(entry) : foodId === null ? null : await findFood(pool, foodId);
    const m = checkManual(f, { basedOn });
    return { ...m, foodId: null, customName: m.name, manual: true };
  }
  throw invalid('food', "food.source must be 'local', 'fatsecret' or 'manual'.");
}

module.exports = { resolveFood };
