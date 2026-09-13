'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  getActiveSession,
  startSession,
  completeSession,
  abandonSession,
  logSet,
  deleteSet,
  lastPerformance,
  completedThisWeek,
} = require('../db/sessions');

/// A non-numeric id reaches MySQL as a bare NaN token and throws
/// ER_BAD_FIELD_ERROR -- not an AppError, so it would surface as a 500. Reject
/// it here as the same 404 the "not found / not yours" branch uses, exactly as
/// routes/plans.js does for plan exercise ids.
function sessionIdOr404(raw) {
  const id = Number.parseInt(raw, 10);
  if (!Number.isInteger(id)) {
    throw AppError.notFound('SESSION_NOT_FOUND', 'No such session.');
  }
  return id;
}

const notFound = () => AppError.notFound('SESSION_NOT_FOUND', 'No such session.');

/// Null and undefined both mean "not recorded" -- a bodyweight set has no
/// weight, and an AMRAP set may have no counted reps.
///
/// Anything else has to be an actual JSON number. Number() and
/// Number.parseInt() coerce far too willingly for a guard whose whole job is
/// rejection: Number('') and Number([]) are both 0 and Number(true) is 1, so
/// `weightKg: ""` used to be STORED as a recorded 0.00 kg lift instead of
/// being rejected or left unrecorded -- while this function read as though it
/// rejected it.
function optionalNumber(value, { code, message, min, max, integer }) {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw AppError.badRequest(code, message);
  }
  if (value < min || value > max) throw AppError.badRequest(code, message);
  // Truncating a fractional rep count would contradict the message this
  // throws, which promises a whole number.
  if (integer && !Number.isInteger(value)) throw AppError.badRequest(code, message);
  return value;
}

module.exports = function buildSessionsRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  // The database stores keys; callers get URLs -- the same contract
  // routes/plans.js states, and the same storage.url() behind it. A client
  // concatenating the raw key onto the API origin asks for
  // /exercises/0001/thumb.jpg instead of /storage/exercises/0001/thumb.jpg,
  // and every thumbnail 404s onto a placeholder for art that exists.
  const toUrl = (key) => (key && deps.storage ? deps.storage.url(key) : null);
  const withUrls = (session) => (session === null || session === undefined ? session : {
    ...session,
    exercises: session.exercises.map((e) => ({ ...e, thumbnailUrl: toUrl(e.thumbnailUrl) })),
  });

  router.get('/active', auth, async (req, res, next) => {
    try {
      // Null rather than 404: having no session in progress is the normal
      // state, the same contract GET /plans/active states.
      res.json({
        data: { session: withUrls(await getActiveSession(deps.pool, req.user.userId)) },
      });
    } catch (err) { next(err); }
  });

  router.get('/week', auth, async (req, res, next) => {
    try {
      res.json({ data: { dates: await completedThisWeek(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });

  router.get('/last-performance', auth, async (req, res, next) => {
    try {
      const raw = typeof req.query.exerciseIds === 'string' ? req.query.exerciseIds : '';
      const ids = raw.split(',')
        .map((part) => Number.parseInt(part, 10))
        .filter(Number.isInteger);
      res.json({
        data: { performances: await lastPerformance(deps.pool, req.user.userId, ids) },
      });
    } catch (err) { next(err); }
  });

  // Shape only. Existence and status are checked inside startSession's
  // transaction, so a curator retiring an exercise mid-request cannot slip
  // between a check here and the insert there.
  //
  // An absent key means "start today's plan session", which is the behaviour
  // that predates this. An empty array is a different thing and is refused:
  // falling through to the plan would silently start a different workout than
  // the one that was asked for.
  const parseExerciseIds = (body) => {
    if (body?.exerciseIds === undefined) return null;

    const ids = body.exerciseIds;
    const bad = () => AppError.badRequest(
      'INVALID_EXERCISE_IDS',
      'exerciseIds must be a non-empty array of exercise ids, without duplicates.',
    );

    if (!Array.isArray(ids) || ids.length === 0) throw bad();
    if (!ids.every((id) => Number.isInteger(id) && id > 0)) throw bad();
    // Left to the unique key this would surface as a 500.
    if (new Set(ids).size !== ids.length) throw bad();
    return ids;
  };

  router.post('/', auth, async (req, res, next) => {
    try {
      const exerciseIds = parseExerciseIds(req.body);
      const { session, created } = await startSession(
        deps.pool, req.user.userId, exerciseIds,
      );
      res.status(created ? 201 : 200).json({ data: { session: withUrls(session) } });
    } catch (err) { next(err); }
  });

  router.post('/:sessionId/complete', auth, async (req, res, next) => {
    try {
      const id = sessionIdOr404(req.params.sessionId);

      const durationMin = Number.parseInt(req.body?.durationMin, 10);
      if (!Number.isInteger(durationMin) || durationMin < 0 || durationMin > 1440) {
        throw AppError.badRequest(
          'DURATION_INVALID',
          'durationMin must be a whole number of minutes between 0 and 1440.',
        );
      }

      const session = await completeSession(deps.pool, req.user.userId, id, durationMin);
      if (!session) throw notFound();
      res.json({ data: { session: withUrls(session) } });
    } catch (err) { next(err); }
  });

  router.post('/:sessionId/abandon', auth, async (req, res, next) => {
    try {
      const id = sessionIdOr404(req.params.sessionId);
      const ok = await abandonSession(deps.pool, req.user.userId, id);
      if (!ok) throw notFound();
      res.json({ data: { abandoned: true } });
    } catch (err) { next(err); }
  });

  router.put('/:sessionId/sets', auth, async (req, res, next) => {
    try {
      const id = sessionIdOr404(req.params.sessionId);

      const setNumber = Number.parseInt(req.body?.setNumber, 10);
      if (!Number.isInteger(setNumber) || setNumber < 1 || setNumber > 99) {
        throw AppError.badRequest('SET_NUMBER_INVALID', 'setNumber must be a whole number from 1 to 99.');
      }

      // DECIMAL(6,2) overflows above 9999.99, and a mistyped 2255 for 22.5
      // should be a message rather than a MySQL error.
      const weightKg = optionalNumber(req.body?.weightKg, {
        code: 'WEIGHT_INVALID',
        message: 'weightKg must be between 0 and 999.99, or null.',
        min: 0, max: 999.99, integer: false,
      });
      const reps = optionalNumber(req.body?.reps, {
        code: 'REPS_INVALID',
        message: 'reps must be a whole number from 0 to 999, or null.',
        min: 0, max: 999, integer: true,
      });

      const exerciseId = Number.parseInt(req.body?.exerciseId, 10);
      if (!Number.isInteger(exerciseId)) {
        // Same code as an id that is real but not in this plan: from the
        // client's side both mean "you cannot log that here".
        throw AppError.badRequest('EXERCISE_NOT_IN_PLAN', 'That exercise is not part of this session.');
      }

      const set = await logSet(deps.pool, req.user.userId, id, { exerciseId, setNumber, weightKg, reps });
      if (!set) throw notFound();
      res.json({ data: { set } });
    } catch (err) { next(err); }
  });

  router.delete('/:sessionId/sets/:exerciseId/:setNumber', auth, async (req, res, next) => {
    try {
      const id = sessionIdOr404(req.params.sessionId);
      const exerciseId = Number.parseInt(req.params.exerciseId, 10);
      const setNumber = Number.parseInt(req.params.setNumber, 10);
      if (!Number.isInteger(exerciseId) || !Number.isInteger(setNumber)) throw notFound();

      const ok = await deleteSet(deps.pool, req.user.userId, id, exerciseId, setNumber);
      if (!ok) throw notFound();

      // 200 with a body, never 204: ApiClient._unwrap requires a `data` object
      // on every response and throws INVALID_RESPONSE without one.
      res.json({ data: { deleted: true } });
    } catch (err) { next(err); }
  });

  return router;
};
