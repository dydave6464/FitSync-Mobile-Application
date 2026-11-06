'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { manilaDay } = require('../lib/manila-day');
const { dailyTarget } = require('../lib/nutrition-target');
const {
  invalid, checkDate, checkServings, checkClientId, checkManual, perServingOf, scaled, round1,
} = require('../lib/nutrition-input');
const { resolveFood } = require('../lib/resolve-food');
const {
  MEALS, insertEntry, insertEntryOnce, findEntryIdByClientId, getEntry, getStoredEntry, updateEntry, deleteEntry, listDayEntries, targetProfile,
} = require('../db/nutrition');

function totalsOf(entries) {
  const t = entries.reduce((a, e) => ({
    kcal: a.kcal + e.kcal, proteinG: a.proteinG + e.proteinG, carbsG: a.carbsG + e.carbsG, fatG: a.fatG + e.fatG,
    fiberG: a.fiberG + (e.fiberG ?? 0), sugarG: a.sugarG + (e.sugarG ?? 0), sodiumMg: a.sodiumMg + (e.sodiumMg ?? 0),
  }), { kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0, sodiumMg: 0 });
  return {
    kcal: t.kcal, proteinG: round1(t.proteinG), carbsG: round1(t.carbsG), fatG: round1(t.fatG),
    fiberG: round1(t.fiberG), sugarG: round1(t.sugarG), sodiumMg: Math.round(t.sodiumMg),
  };
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
      const clientId = checkClientId(b.clientId);
      const { userId } = req.user;

      // Try again after a save that did land: the entry already saved, as it
      // is now, and the body is not compared. Looked up before the food, so a
      // repeat never asks FatSecret again.
      if (clientId) {
        const savedId = await findEntryIdByClientId(pool, userId, clientId);
        const saved = savedId === null ? null : await getEntry(pool, userId, savedId);
        if (saved) return res.json({ data: { entry: saved } });
      }

      const base = await resolveFood(deps, b.food, userId);
      const e = {
        date, mealType: b.mealType, servings,
        foodId: base.foodId, customName: base.customName, servingDesc: base.servingDesc,
        ...scaled(base, servings),
        loggedVia: base.manual ? 'manual' : 'search',
      };
      const { id, created } = clientId
        ? await insertEntryOnce(pool, userId, e, clientId)
        : { id: await insertEntry(pool, userId, e), created: true };
      res.status(created ? 201 : 200).json({ data: { entry: await getEntry(pool, userId, id) } });
    } catch (err) { next(err); }
  });

  router.patch('/entries/:id', auth, async (req, res, next) => {
    try {
      const b = req.body || {};
      if (!MEALS.includes(b.mealType)) throw invalid('mealType', `mealType must be one of: ${MEALS.join(', ')}.`);
      const servings = checkServings(b.servings);
      // Only the user's own numbers: swapping in another catalogue or
      // FatSecret food is a delete and a fresh log, not an edit.
      if (b.food !== undefined && (b.food === null || typeof b.food !== 'object' || b.food.source !== 'manual')) {
        throw invalid('food', "food.source must be 'manual'.");
      }

      const id = Number(req.params.id);
      const stored = Number.isInteger(id) && id > 0 ? await getStoredEntry(pool, req.user.userId, id) : null;
      if (!stored) throw AppError.notFound('ENTRY_NOT_FOUND', 'No such entry.');

      // From the entry's own numbers, never the foods row: a later
      // correction to the food list must not rewrite history.
      const perServing = perServingOf(stored);
      // The entry is the basis: unchanged protein, carbs and fat keep its kcal.
      const manual = b.food === undefined ? null : checkManual(b.food, { basedOn: perServing });

      let food; // { foodId, customName, servingDesc, loggedVia } and the multiplied numbers
      if (manual) {
        food = {
          foodId: null, customName: manual.name, servingDesc: manual.servingDesc, loggedVia: 'manual',
          ...scaled(manual, servings),
        };
      } else if (servings === stored.servings) {
        // Untouched: a guard, so a later change that rounds per serving
        // can't alter what was logged.
        food = stored;
      } else {
        food = { ...stored, ...scaled(perServing, servings) };
      }

      await updateEntry(pool, req.user.userId, id, { ...food, mealType: b.mealType, servings });
      // Deleted between the read above and the write: nothing to answer with.
      const entry = await getEntry(pool, req.user.userId, id);
      if (!entry) throw AppError.notFound('ENTRY_NOT_FOUND', 'No such entry.');
      res.json({ data: { entry } });
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
