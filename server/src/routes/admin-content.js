'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const {
  invalidAdminField, idParam, searchParam, pagingParams, bodyOf,
} = require('../lib/admin-params');
const {
  STATUSES, asAdminExercise, listAdminExercises, publishExercise, unpublishExercise,
} = require('../db/admin-exercises');
const {
  SHOW, listAdminFoods, createFood, updateFood, setFoodHidden,
} = require('../db/admin-foods');

function noSuchExercise() {
  return AppError.notFound('EXERCISE_NOT_FOUND', 'No such exercise.');
}

function noSuchFood() {
  return AppError.notFound('FOOD_NOT_FOUND', 'No such food.');
}

/// The admin Content area: exercise demos (Animations) and FitSync's own
/// foods (Meals). Mounted inside buildAdminRouter, so every route here is
/// already behind requireAdmin.
function buildAdminContentRouter({ pool, storage = null }) {
  const router = express.Router();
  // The database stores keys; callers get URLs (as routes/exercises.js).
  const toUrl = (key) => (key && storage ? storage.url(key) : null);

  router.get('/exercises', async (req, res, next) => {
    try {
      const { status } = req.query;
      if (typeof status !== 'string' || !STATUSES.includes(status)) {
        throw invalidAdminField('status', 'status must be pending or live.');
      }
      const q = searchParam(req.query.q);
      const { page, limit } = pagingParams(req.query);
      const { rows, counts, total } = await listAdminExercises(pool, { status, q, page, limit });
      res.json({
        data: { exercises: rows.map((r) => asAdminExercise(r, toUrl)), counts, page, limit, total },
      });
    } catch (err) {
      next(err);
    }
  });

  // Repeat calls are harmless: each answers the exercise as it now is.
  const changes = {
    publish: (exerciseId, req) => publishExercise(pool, exerciseId, req.admin.adminId),
    unpublish: (exerciseId) => unpublishExercise(pool, exerciseId),
  };
  for (const [action, apply] of Object.entries(changes)) {
    router.post(`/exercises/:id/${action}`, async (req, res, next) => {
      try {
        const exerciseId = idParam(req.params.id);
        const row = exerciseId === null ? null : await apply(exerciseId, req);
        if (!row) throw noSuchExercise();
        res.json({ data: { exercise: asAdminExercise(row, toUrl) } });
      } catch (err) {
        next(err);
      }
    });
  }

  router.get('/foods', async (req, res, next) => {
    try {
      const { show } = req.query;
      if (typeof show !== 'string' || !Object.hasOwn(SHOW, show)) {
        throw invalidAdminField('show', 'show must be shown or hidden.');
      }
      const q = searchParam(req.query.q);
      const { page, limit } = pagingParams(req.query);
      const { foods, counts, total } = await listAdminFoods(pool, { show, q, page, limit });
      res.json({ data: { foods, counts, page, limit, total } });
    } catch (err) {
      next(err);
    }
  });

  router.post('/foods', async (req, res, next) => {
    try {
      const food = await createFood(pool, bodyOf(req), req.admin.adminId);
      res.status(201).json({ data: { food } });
    } catch (err) {
      next(err);
    }
  });

  router.patch('/foods/:id', async (req, res, next) => {
    try {
      const foodId = idParam(req.params.id);
      const food = foodId === null ? null : await updateFood(pool, foodId, bodyOf(req), req.admin.adminId);
      if (!food) throw noSuchFood();
      res.json({ data: { food } });
    } catch (err) {
      next(err);
    }
  });

  // Repeat calls are harmless: each answers the food as it now is.
  for (const [action, hidden] of [['hide', true], ['show', false]]) {
    router.post(`/foods/:id/${action}`, async (req, res, next) => {
      try {
        const foodId = idParam(req.params.id);
        const food = foodId === null ? null : await setFoodHidden(pool, foodId, hidden);
        if (!food) throw noSuchFood();
        res.json({ data: { food } });
      } catch (err) {
        next(err);
      }
    });
  }

  return router;
}

module.exports = { buildAdminContentRouter };
