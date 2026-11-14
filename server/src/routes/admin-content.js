'use strict';
const crypto = require('node:crypto');
const express = require('express');
const AppError = require('../lib/app-error');
const { checkImage } = require('../lib/image-check');
const {
  invalidAdminField, idParam, searchParam, pagingParams, bodyOf,
} = require('../lib/admin-params');
const {
  STATUSES, asAdminExercise, listAdminExercises, publishExercise, unpublishExercise,
} = require('../db/admin-exercises');
const {
  SHOW, listAdminFoods, findOwnFood, createFood, updateFood, setFoodHidden,
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

  /// The admin food as answered: photoUrl from its key; the key itself is never sent.
  const answerFood = ({ photoKey, ...food }) => ({ ...food, photoUrl: toUrl(photoKey) });

  /// [body]'s photo intent: { image } to store, { remove: true }, or {} to
  /// keep. Anything else about photos (a photoKey, say) is ignored.
  function photoIntent(body) {
    const hasImage = body.image !== undefined || body.mimeType !== undefined;
    if (body.removePhoto !== undefined) {
      if (body.removePhoto !== true) throw invalidAdminField('removePhoto', 'removePhoto must be true when sent.');
      if (hasImage) throw invalidAdminField('removePhoto', 'Send a new photo or removePhoto, not both.');
      return { remove: true };
    }
    return hasImage ? { image: checkImage(body, { noun: 'photo' }) } : {};
  }

  /// Stores a checked photo and answers its key.
  async function storePhoto({ bytes, ext }, mimeType) {
    const key = `foods/${crypto.randomUUID()}.${ext}`;
    await storage.put(key, bytes, mimeType);
    return key;
  }

  /// A photo file nothing references any more; a failure is logged, never fatal.
  async function dropPhoto(key, req) {
    if (!key) return;
    try {
      await storage.delete(key);
    } catch (err) {
      req.log?.warn({ code: err?.code ?? null }, 'old food photo not deleted');
    }
  }

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
        throw invalidAdminField('show', 'show must be shown, hidden or suggested.');
      }
      const q = searchParam(req.query.q);
      const { page, limit } = pagingParams(req.query);
      const { foods, counts, total } = await listAdminFoods(pool, { show, q, page, limit });
      res.json({ data: { foods: foods.map(answerFood), counts, page, limit, total } });
    } catch (err) {
      next(err);
    }
  });

  router.post('/foods', async (req, res, next) => {
    try {
      const body = bodyOf(req);
      const intent = photoIntent(body);
      const photoKey = intent.image ? await storePhoto(intent.image, body.mimeType) : null;
      let food;
      try {
        food = await createFood(pool, body, req.admin.adminId, { photoKey });
      } catch (err) {
        await dropPhoto(photoKey, req);
        throw err;
      }
      res.status(201).json({ data: { food: answerFood(food) } });
    } catch (err) {
      next(err);
    }
  });

  router.patch('/foods/:id', async (req, res, next) => {
    try {
      const foodId = idParam(req.params.id);
      const existing = foodId === null ? null : await findOwnFood(pool, foodId);
      if (!existing) throw noSuchFood();
      const body = bodyOf(req);
      const intent = photoIntent(body);
      const newKey = intent.image ? await storePhoto(intent.image, body.mimeType) : null;
      let photoKey;
      if (intent.image) photoKey = newKey;
      else if (intent.remove) photoKey = null;
      let food;
      try {
        food = await updateFood(pool, foodId, body, req.admin.adminId, { photoKey });
      } catch (err) {
        await dropPhoto(newKey, req);
        throw err;
      }
      if (!food) {
        await dropPhoto(newKey, req);
        throw noSuchFood();
      }
      if (photoKey !== undefined && existing.photoKey !== photoKey) await dropPhoto(existing.photoKey, req);
      res.json({ data: { food: answerFood(food) } });
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
        res.json({ data: { food: answerFood(food) } });
      } catch (err) {
        next(err);
      }
    });
  }

  return router;
}

module.exports = { buildAdminContentRouter };
