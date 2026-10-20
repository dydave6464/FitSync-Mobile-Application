'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { searchOwnFoods } = require('../db/foods');
const { listRecentFoods } = require('../db/nutrition');

const MIN_Q = 2;
const MAX_Q = 60;
const LIMIT = 20;
// FitSync's own foods per search; FatSecret's stay at LIMIT.
const OWN_LIMIT = 30;
const MAX_EXTERNAL_ID = 64;
// The whole FatSecret search (token + request) gets this long before the
// response goes out with FitSync's own foods alone.
const FATSECRET_TIMEOUT_MS = 3000;

function own(f) {
  return {
    id: f.foodId, source: 'local', externalId: null, name: f.name, servingDesc: f.servingDesc,
    kcal: f.kcal, proteinG: f.proteinG, carbsG: f.carbsG, fatG: f.fatG, fiberG: f.fiberG ?? null,
    sugarG: f.sugarG ?? null, sodiumMg: f.sodiumMg ?? null, group: f.group ?? null,
  };
}

function fromFatsecret(f) {
  return {
    id: null, source: 'fatsecret', externalId: f.externalId, name: f.name, servingDesc: f.servingDesc,
    kcal: f.kcal, proteinG: f.proteinG, carbsG: f.carbsG, fatG: f.fatG, fiberG: f.fiberG ?? null,
    sugarG: f.sugarG ?? null, sodiumMg: f.sodiumMg ?? null, group: null,
  };
}

/// FatSecret's results, or null when it failed or ran out of time. A search
/// failure is swallowed into null for the caller (FitSync's own foods still
/// come back with a 200), but it is still logged -- a silent 502 upstream
/// must leave a server-side trace. A timeout is not logged: FatSecret being
/// slow isn't a failure worth a warning every time -- including the abort the
/// client's own timer raises a moment after this one gives up.
async function searchFatsecret(fatsecret, q, logger) {
  if (!fatsecret) return null;
  let timer;
  let timedOut = false;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => {
      timedOut = true;
      resolve(null);
    }, fatsecret.timeoutMs || FATSECRET_TIMEOUT_MS);
  });
  try {
    return await Promise.race([
      fatsecret.search(q).catch((e) => {
        if (logger && !timedOut) logger.warn({ err: e.message }, 'FatSecret food search failed');
        return null;
      }),
      timeout,
    ]);
  } finally {
    clearTimeout(timer);
  }
}

module.exports = function buildFoodsRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/search', auth, async (req, res, next) => {
    try {
      const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
      if (q.length < MIN_Q || q.length > MAX_Q) {
        throw AppError.badRequest('INVALID_FOOD_QUERY', `q must be ${MIN_Q} to ${MAX_Q} characters.`);
      }
      const [mine, theirs] = await Promise.all([
        searchOwnFoods(deps.pool, q, OWN_LIMIT), searchFatsecret(deps.fatsecret, q, deps.logger),
      ]);
      res.json({
        data: {
          foods: [...mine.map(own), ...(theirs || []).slice(0, LIMIT).map(fromFatsecret)],
          fatsecretUnavailable: theirs === null,
        },
      });
    } catch (err) { next(err); }
  });

  // The detailed serving behind one FatSecret id -- the same food.get.v2 call
  // the logging route makes -- so the log sheet can preview exactly what
  // gets logged instead of the search description line.
  router.get('/fatsecret/:externalId', auth, async (req, res, next) => {
    try {
      const { externalId } = req.params;
      if (typeof externalId !== 'string' || externalId === '' || externalId.length > MAX_EXTERNAL_ID) {
        throw AppError.badRequest('INVALID_FOOD_QUERY', `externalId must be 1 to ${MAX_EXTERNAL_ID} characters.`);
      }
      let food;
      try {
        food = deps.fatsecret ? await deps.fatsecret.get(externalId) : undefined;
      } catch (e) {
        if (deps.logger) deps.logger.warn({ externalId, err: e.message }, 'FatSecret food lookup failed');
        food = undefined;
      }
      if (food === undefined) {
        throw new AppError(502, 'FATSECRET_UNAVAILABLE', "Couldn't reach FatSecret. Try again, or add the food manually.");
      }
      if (food === null) throw AppError.notFound('FOOD_NOT_FOUND', 'FatSecret has no such food.');
      res.json({ data: { food: fromFatsecret(food) } });
    } catch (err) { next(err); }
  });

  router.get('/recent', auth, async (req, res, next) => {
    try {
      res.json({ data: { foods: await listRecentFoods(deps.pool, req.user.userId, LIMIT) } });
    } catch (err) { next(err); }
  });

  return router;
};
