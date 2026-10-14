'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { manilaDay } = require('../lib/manila-day');
const { dailyTarget } = require('../lib/nutrition-target');
const { findFood, upsertFatsecretFood } = require('../db/foods');
const {
  MEALS, insertEntry, getEntry, deleteEntry, listDayEntries, targetProfile,
} = require('../db/nutrition');

const MAX_SERVINGS = 20;
const MAX_GRAMS = 500;
const MAX_NAME = 100;
const MAX_SERVING_DESC = 60;
const round1 = (n) => Math.round(n * 10) / 10;
const round2 = (n) => Math.round(n * 100) / 100;

function invalid(field, message) {
  return AppError.badRequest('INVALID_NUTRITION_FIELD', message, [{ field }]);
}

/// A real calendar date, not after today in Manila. Undefined -> today.
function checkDate(value) {
  const today = manilaDay();
  if (value === undefined) return today;
  const ok = typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
  if (!ok) throw AppError.badRequest('INVALID_DATE', 'date must be a real date as YYYY-MM-DD.');
  if (value > today) throw AppError.badRequest('INVALID_DATE', 'date cannot be in the future.');
  return value;
}

function checkServings(s) {
  if (typeof s !== 'number' || !Number.isFinite(s) || s < 0.5 || s > MAX_SERVINGS || !Number.isInteger(s * 2)) {
    throw invalid('servings', `servings must be 0.5 to ${MAX_SERVINGS}, in steps of 0.5.`);
  }
  return s;
}

function checkManual(food) {
  const name = typeof food.name === 'string' ? food.name.trim() : '';
  if (name.length < 1 || name.length > MAX_NAME) throw invalid('name', `name must be 1 to ${MAX_NAME} characters.`);
  let servingDesc = null;
  if (food.servingDesc != null) {
    if (typeof food.servingDesc !== 'string') throw invalid('servingDesc', 'servingDesc must be text.');
    servingDesc = food.servingDesc.trim() || null;
    if (servingDesc && servingDesc.length > MAX_SERVING_DESC) {
      throw invalid('servingDesc', `servingDesc must be at most ${MAX_SERVING_DESC} characters.`);
    }
  }
  const grams = {};
  for (const k of ['proteinG', 'carbsG', 'fatG']) {
    const g = food[k];
    if (typeof g !== 'number' || !Number.isFinite(g) || g < 0 || g > MAX_GRAMS) {
      throw invalid(k, `${k} must be 0 to ${MAX_GRAMS}.`);
    }
    grams[k] = round2(g);
  }
  if (grams.proteinG + grams.carbsG + grams.fatG === 0) {
    throw invalid('food', 'A manual food needs some protein, carbs or fat.');
  }
  const kcal = Math.round(4 * grams.proteinG + 4 * grams.carbsG + 9 * grams.fatG);
  return { name, servingDesc, kcal, ...grams };
}

function totalsOf(entries) {
  const t = entries.reduce((a, e) => ({
    kcal: a.kcal + e.kcal, proteinG: a.proteinG + e.proteinG, carbsG: a.carbsG + e.carbsG, fatG: a.fatG + e.fatG,
  }), { kcal: 0, proteinG: 0, carbsG: 0, fatG: 0 });
  return { kcal: t.kcal, proteinG: round1(t.proteinG), carbsG: round1(t.carbsG), fatG: round1(t.fatG) };
}

module.exports = function buildNutritionRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);
  const { pool } = deps;

  router.get('/day', auth, async (req, res, next) => {
    try {
      const date = checkDate(req.query.date);
      const userId = req.user.userId;
      const [entries, profile] = await Promise.all([
        listDayEntries(pool, userId, date), targetProfile(pool, userId),
      ]);
      const { target, missing } = dailyTarget(profile, manilaDay());
      const meals = Object.fromEntries(MEALS.map((m) => [m, entries.filter((e) => e.mealType === m)]));
      res.json({ data: { day: { date, target, targetMissing: missing, totals: totalsOf(entries), meals } } });
    } catch (err) { next(err); }
  });

  router.post('/entries', auth, async (req, res, next) => {
    try {
      const b = req.body || {};
      const date = checkDate(b.date);
      if (!MEALS.includes(b.mealType)) throw invalid('mealType', `mealType must be one of: ${MEALS.join(', ')}.`);
      const servings = checkServings(b.servings);
      const food = b.food || {};

      let base; // per serving: { foodId, customName, servingDesc, kcal, proteinG, carbsG, fatG }
      let loggedVia = 'search';
      if (food.source === 'local') {
        const found = Number.isInteger(food.id) ? await findFood(pool, food.id) : null;
        if (!found) throw AppError.notFound('FOOD_NOT_FOUND', 'That food is not in the list.');
        base = { ...found, customName: null, servingDesc: null };
      } else if (food.source === 'fatsecret') {
        if (typeof food.externalId !== 'string' || food.externalId === '' || food.externalId.length > 64) {
          throw invalid('food', 'externalId is required for a FatSecret food.');
        }
        let fetched;
        try {
          fetched = deps.fatsecret ? await deps.fatsecret.get(food.externalId) : undefined;
        } catch (e) {
          // The 502 below is deliberately generic -- "FatSecret is down" --
          // but that must not also be true of a real bug on our side (a bad
          // externalId we built, a client misuse). Log the message only:
          // never the whole error object (stack may embed request internals)
          // or anything from the request itself.
          if (deps.logger) deps.logger.warn({ externalId: food.externalId, err: e.message }, 'FatSecret food lookup failed');
          fetched = undefined;
        }
        if (fetched === undefined) {
          throw new AppError(502, 'FATSECRET_UNAVAILABLE', "Couldn't reach FatSecret. Try again, or add the food manually.");
        }
        if (fetched === null) throw AppError.notFound('FOOD_NOT_FOUND', 'FatSecret has no such food.');
        const foodId = await upsertFatsecretFood(pool, fetched);
        base = { ...fetched, foodId, customName: null, servingDesc: null };
      } else if (food.source === 'manual') {
        const m = checkManual(food);
        base = { ...m, foodId: null, customName: m.name };
        loggedVia = 'manual';
      } else {
        throw invalid('food', "food.source must be 'local', 'fatsecret' or 'manual'.");
      }

      const id = await insertEntry(pool, req.user.userId, {
        date, mealType: b.mealType, servings,
        foodId: base.foodId, customName: base.customName, servingDesc: base.servingDesc,
        kcal: Math.round(base.kcal * servings),
        proteinG: round2(base.proteinG * servings),
        carbsG: round2(base.carbsG * servings),
        fatG: round2(base.fatG * servings),
        loggedVia,
      });
      res.status(201).json({ data: { entry: await getEntry(pool, req.user.userId, id) } });
    } catch (err) { next(err); }
  });

  router.delete('/entries/:id', auth, async (req, res, next) => {
    try {
      const id = Number(req.params.id);
      const gone = Number.isInteger(id) && id > 0 && await deleteEntry(pool, req.user.userId, id);
      if (!gone) throw AppError.notFound('ENTRY_NOT_FOUND', 'No such entry.');
      res.json({ data: { deleted: true } });
    } catch (err) { next(err); }
  });

  return router;
};
