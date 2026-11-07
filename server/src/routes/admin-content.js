'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const { parsePositiveInt } = require('../lib/query-params');
const {
  STATUSES, asAdminExercise, listAdminExercises, publishExercise, unpublishExercise,
} = require('../db/admin-exercises');

const DEFAULT_LIMIT = 30;
const MAX_LIMIT = 50;

function invalid(field, message) {
  return AppError.badRequest('INVALID_ADMIN_FIELD', message, [{ field }]);
}

function noSuchExercise() {
  return AppError.notFound('EXERCISE_NOT_FOUND', 'No such exercise.');
}

/// The :id of a route, or null when it can't name a row (then the answer is
/// the same 404 as an unknown id).
function idParam(raw) {
  return /^[1-9]\d{0,9}$/.test(raw) ? Number(raw) : null;
}

/// A single search text, or a 400: a repeated key arrives as an array
/// (Express 5's query parser).
function searchParam(raw) {
  if (raw === undefined) return '';
  if (typeof raw !== 'string') throw invalid('q', 'q must be a single search text.');
  return raw;
}

/// The admin Content area: exercise demos (Animations). Mounted inside
/// buildAdminRouter, so every route here is already behind requireAdmin.
function buildAdminContentRouter({ pool, storage = null }) {
  const router = express.Router();
  // The database stores keys; callers get URLs (as routes/exercises.js).
  const toUrl = (key) => (key && storage ? storage.url(key) : null);

  router.get('/exercises', async (req, res, next) => {
    try {
      const { status } = req.query;
      if (typeof status !== 'string' || !STATUSES.includes(status)) {
        throw invalid('status', 'status must be pending or live.');
      }
      const q = searchParam(req.query.q);
      const page = parsePositiveInt('page', req.query.page, 1);
      const limit = parsePositiveInt('limit', req.query.limit, DEFAULT_LIMIT, MAX_LIMIT);
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

  return router;
}

module.exports = { buildAdminContentRouter };
