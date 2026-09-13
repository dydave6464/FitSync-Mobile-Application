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

// Express 5's default query parser turns a repeated key (?equipment=a&
// equipment=b) into an array. mysql2 happily formats an array as a comma
// list, which reaches the database as a syntax error instead of a 400 — so
// a parameter whose predicate is written for a single value must reject
// anything that isn't a plain string before it gets near pool.query.
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

// muscleGroup is the one filter that may repeat, so a caller can ask for a
// whole training day at once — a 'Push' day is pectorals + delts + triceps.
// The array goes to a predicate written for a list (`IN (?)`, see
// src/db/exercises.js), where mysql2's comma expansion is exactly right, but
// only for non-empty strings: an object element would format as the literal
// '[object Object]' and an empty one as '', both of which match nothing while
// looking like a filter that worked.
function parseOptionalStringList(name, raw) {
  if (raw === undefined || raw === '') return null;
  if (typeof raw === 'string') return raw;
  const isListOfValues = Array.isArray(raw) && raw.length > 0
    && raw.every((value) => typeof value === 'string' && value !== '');
  if (!isListOfValues) {
    throw AppError.badRequest(
      'INVALID_QUERY_PARAM',
      `${name} must be a string, or several non-empty strings.`,
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
    // A real boolean: MySQL answers EXISTS with 1/0, and a client reading
    // that as truthy-by-accident would be right today and wrong the moment
    // the column is selected differently.
    contraindicated: Boolean(row.contraindicated),
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
        muscleGroup: parseOptionalStringList('muscleGroup', req.query.muscleGroup),
        equipment: parseOptionalString('equipment', req.query.equipment),
        // Marks the rows that load a region this caller has reported an
        // injury in. The router is mounted behind requireAuth, so there is
        // always someone to answer for.
        userId: req.user.userId,
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
      const row = await getExerciseById(pool, id, req.user.userId);
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
