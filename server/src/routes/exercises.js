'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const {
  listExercises,
  getExerciseById,
  listFilters,
  DEFAULT_LIMIT,
  MAX_LIMIT,
} = require('../db/exercises');

// A client sending nonsense should learn that it did, rather than have the
// value silently clamped and get results it did not ask for.
function parsePositiveInt(name, raw, fallback, max = null) {
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 1) {
    throw AppError.badRequest(
      'INVALID_QUERY_PARAM',
      `${name} must be a positive integer.`,
      [{ field: name, value: String(raw) }],
    );
  }
  if (max !== null && value > max) {
    throw AppError.badRequest(
      'INVALID_QUERY_PARAM',
      `${name} must not exceed ${max}.`,
      [{ field: name, value: String(raw) }],
    );
  }
  return value;
}

// Express 5's default query parser turns a repeated key (?muscleGroup=a&
// muscleGroup=b) into an array. mysql2 happily formats an array as a comma
// list, which reaches the database as a syntax error instead of a 400 — so
// this must reject anything that isn't a plain string before it gets near
// pool.query.
function parseOptionalString(name, raw) {
  if (raw === undefined || raw === '') return null;
  if (typeof raw !== 'string') {
    throw AppError.badRequest(
      'INVALID_QUERY_PARAM',
      `${name} must be a single string value.`,
      [{ field: name, value: String(raw) }],
    );
  }
  return raw;
}

module.exports = function buildExercisesRouter({ pool, storage }) {
  const router = express.Router();

  // The database stores keys; callers get URLs. This is the whole reason the
  // seed stored keys rather than resolved paths.
  const toUrl = (key) => (key && storage ? storage.url(key) : null);

  const toSummary = (row) => ({
    exerciseId: row.exercise_id,
    name: row.name,
    muscleGroup: row.muscle_group,
    equipment: row.equipment,
    thumbnailUrl: toUrl(row.thumbnail_url),
  });

  // MUST come before '/:id'. Registered after it, ':id' captures the literal
  // string 'filters' and this endpoint becomes unreachable.
  router.get('/filters', async (req, res, next) => {
    try {
      const { muscleGroups, equipment } = await listFilters(pool);
      res.json({ data: { muscleGroups, equipment } });
    } catch (err) {
      next(err);
    }
  });

  router.get('/', async (req, res, next) => {
    try {
      const page = parsePositiveInt('page', req.query.page, 1);
      const limit = parsePositiveInt('limit', req.query.limit, DEFAULT_LIMIT, MAX_LIMIT);

      const { rows, total } = await listExercises(pool, {
        muscleGroup: parseOptionalString('muscleGroup', req.query.muscleGroup),
        equipment: parseOptionalString('equipment', req.query.equipment),
        page,
        limit,
      });

      res.json({ data: { exercises: rows.map(toSummary), page, limit, total } });
    } catch (err) {
      next(err);
    }
  });

  router.get('/:id', async (req, res, next) => {
    try {
      const id = parsePositiveInt('id', req.params.id, null);
      const row = await getExerciseById(pool, id);
      if (!row) {
        throw AppError.notFound(
          'EXERCISE_NOT_FOUND',
          `No live exercise with id ${req.params.id}.`,
        );
      }
      res.json({
        data: {
          ...toSummary(row),
          animationUrl: toUrl(row.animation_url),
          cues: row.cues,
        },
      });
    } catch (err) {
      next(err);
    }
  });

  return router;
};
