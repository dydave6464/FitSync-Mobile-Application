'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { getActivePlan, savePlan, createPlanFromSession } = require('../db/plans');
const { getProfile } = require('../db/profile');
const { getActiveSession } = require('../db/sessions');
const { loadSwapContext, listAlternatives, swapPlanExercise } = require('../db/plan-swap');

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

function parseLimit(raw) {
  if (raw === undefined) return DEFAULT_LIMIT;
  const n = Number.parseInt(raw, 10);
  if (!Number.isInteger(n) || n < 1) return DEFAULT_LIMIT;
  return Math.min(n, MAX_LIMIT);
}

const SPLIT_STYLES = ['full_body', 'push_pull_legs', 'upper_lower', 'cardio_core'];
const MIN_DAYS = 1;
const MAX_DAYS = 7;
const MIN_SESSION_MIN = 20;
const MAX_SESSION_MIN = 120;

function invalidPlanField(field, message) {
  return AppError.badRequest('INVALID_PLAN_FIELD', message, [{ field }]);
}

// Validated here rather than in the ML service, which is deliberately
// permissive: a bad value from OUR OWN client is a bug worth reporting, while
// a bad value reaching the generator should still produce a plan.
function validateOverrides(body) {
  const overrides = {};

  if (body?.splitStyle !== undefined && body.splitStyle !== null) {
    if (!SPLIT_STYLES.includes(body.splitStyle)) {
      throw invalidPlanField('splitStyle', `splitStyle must be one of ${SPLIT_STYLES.join(', ')}.`);
    }
    overrides.splitStyle = body.splitStyle;
  }

  if (body?.daysPerWeek !== undefined && body.daysPerWeek !== null) {
    const days = body.daysPerWeek;
    if (!Number.isInteger(days) || days < MIN_DAYS || days > MAX_DAYS) {
      throw invalidPlanField('daysPerWeek', `daysPerWeek must be a whole number from ${MIN_DAYS} to ${MAX_DAYS}.`);
    }
    overrides.daysPerWeek = days;
  }

  if (body?.sessionLengthMin !== undefined && body.sessionLengthMin !== null) {
    const length = body.sessionLengthMin;
    if (!Number.isInteger(length) || length < MIN_SESSION_MIN || length > MAX_SESSION_MIN) {
      throw invalidPlanField('sessionLengthMin', `sessionLengthMin must be a whole number from ${MIN_SESSION_MIN} to ${MAX_SESSION_MIN}.`);
    }
    overrides.sessionLengthMin = length;
  }

  return overrides;
}

module.exports = function buildPlansRouter(deps) {
  const router = express.Router();

  // The database stores keys; callers get URLs -- the same contract
  // routes/exercises.js states, and the same storage.url() behind it. The plan
  // paths returned the raw key, so a client concatenating it onto the API
  // origin asked for /exercises/0001/thumb.jpg instead of
  // /storage/exercises/0001/thumb.jpg: every thumbnail in the plan 404'd and
  // fell back to a placeholder, for exercises that all have artwork.
  const toUrl = (key) => (key && deps.storage ? deps.storage.url(key) : null);
  const withUrls = (plan) => (plan === null ? null : {
    ...plan,
    exercises: plan.exercises.map((e) => ({ ...e, thumbnailUrl: toUrl(e.thumbnailUrl) })),
  });

  router.get('/active', requireAuth(deps), async (req, res, next) => {
    try {
      // Null rather than 404: "you have no plan yet" is a normal state during
      // onboarding, not a missing resource.
      res.json({
        data: { plan: withUrls(await getActivePlan(deps.pool, req.user.userId)) },
      });
    } catch (err) { next(err); }
  });

  router.post('/regenerate', requireAuth(deps), async (req, res, next) => {
    try {
      const userId = req.user.userId;
      const overrides = validateOverrides(req.body);

      // Replacing the plan under a running workout would strand the logger on
      // exercises no longer in it. Refusing is honest; finish or discard first.
      if (await getActiveSession(deps.pool, userId)) {
        throw AppError.conflict(
          'SESSION_IN_PROGRESS',
          'Finish or discard your current session before changing your plan.',
        );
      }

      // A generated plan is the machine's to replace. One the user built out
      // of workouts they actually did is not, and savePlan deactivates the
      // active plan inside its transaction -- so without this the work is gone
      // on one tap. Refused server-side rather than warned client-side so the
      // protection holds for any caller, not only a screen that remembered.
      const current = await getActivePlan(deps.pool, userId);
      if (current !== null && current.source === 'custom' && req.body?.replaceCustomPlan !== true) {
        const dayCount = new Set(current.exercises.map((e) => e.dayNo)).size;
        throw AppError.conflict(
          'CUSTOM_PLAN_WOULD_BE_LOST',
          `Generating a new plan replaces "${current.name}" and the `
            + `${dayCount} ${dayCount === 1 ? 'day' : 'days'} you built in it.`,
        );
      }

      // Read server-side, so the client cannot regenerate against someone
      // else's profile by sending one.
      const profile = await getProfile(deps.pool, userId);
      const generated = await deps.ml.generatePlan({ ...profile, overrides });
      await savePlan(deps.pool, userId, generated);

      res.json({ data: { plan: withUrls(await getActivePlan(deps.pool, userId)) } });
    } catch (err) { next(err); }
  });

  router.post('/from-session', requireAuth(deps), async (req, res, next) => {
    try {
      const userId = req.user.userId;

      const sessionId = req.body?.sessionId;
      if (!Number.isInteger(sessionId) || sessionId < 1) {
        throw invalidPlanField('sessionId', 'sessionId must be a positive integer.');
      }

      const dayNo = req.body?.dayNo ?? null;
      if (dayNo !== null && (!Number.isInteger(dayNo) || dayNo < 1)) {
        throw invalidPlanField('dayNo', 'dayNo must be a positive integer.');
      }

      // Required only when this call CREATES the plan. Checked here rather
      // than in the db layer so the 400 names the field, and read from the
      // active plan's source so the client need not track which case it is in.
      const active = await getActivePlan(deps.pool, userId);
      const creating = active === null || active.source !== 'custom';
      const splitStyle = req.body?.splitStyle;
      if (creating) {
        if (typeof splitStyle !== 'string' || !SPLIT_STYLES.includes(splitStyle)) {
          throw invalidPlanField(
            'splitStyle',
            `splitStyle must be one of ${SPLIT_STYLES.join(', ')}.`,
          );
        }
      }

      // Changing the plan under a running workout would strand the logger on
      // exercises no longer in it. Same guard, same reason, as regenerate.
      if (await getActiveSession(deps.pool, userId)) {
        throw AppError.conflict(
          'SESSION_IN_PROGRESS',
          'Finish or discard your current session before changing your plan.',
        );
      }

      await createPlanFromSession(deps.pool, userId, { sessionId, splitStyle, dayNo });

      res.json({ data: { plan: withUrls(await getActivePlan(deps.pool, userId)) } });
    } catch (err) { next(err); }
  });

  router.get('/exercises/:planExerciseId/alternatives', requireAuth(deps), async (req, res, next) => {
    try {
      const id = Number.parseInt(req.params.planExerciseId, 10);
      // A non-numeric id parses to NaN, and mysql2 passes NaN through as the
      // bare token NaN rather than converting it -- MySQL then reads it as an
      // unknown column and throws ER_BAD_FIELD_ERROR, which is not an
      // AppError and would otherwise surface as a 500. Reject it as the same
      // "no such row" 404 up front, before it reaches the query.
      if (!Number.isInteger(id)) {
        throw AppError.notFound('PLAN_EXERCISE_NOT_FOUND', 'No such plan exercise.');
      }
      const ctx = await loadSwapContext(deps.pool, req.user.userId, id);
      // 404 for both "no such row" and "not yours", so the response cannot be
      // used to discover which plan rows exist.
      if (!ctx) throw AppError.notFound('PLAN_EXERCISE_NOT_FOUND', 'No such plan exercise.');

      const q = typeof req.query.q === 'string' && req.query.q.trim() ? req.query.q.trim() : null;
      const bodyweightOnly = req.query.bodyweightOnly === '1';
      const alternatives = await listAlternatives(deps.pool, ctx, {
        q, limit: parseLimit(req.query.limit), bodyweightOnly,
      });
      res.json({
        data: {
          alternatives: alternatives.map(
            (a) => ({ ...a, thumbnailUrl: toUrl(a.thumbnailUrl) }),
          ),
        },
      });
    } catch (err) { next(err); }
  });

  router.patch('/exercises/:planExerciseId', requireAuth(deps), async (req, res, next) => {
    try {
      const id = Number.parseInt(req.params.planExerciseId, 10);
      // See the alternatives route above: NaN reaches MySQL as a bare
      // identifier and throws ER_BAD_FIELD_ERROR, not an AppError. Reject it
      // here as the same 404 the "not found / not yours" branch below uses.
      if (!Number.isInteger(id)) {
        throw AppError.notFound('PLAN_EXERCISE_NOT_FOUND', 'No such plan exercise.');
      }
      const ctx = await loadSwapContext(deps.pool, req.user.userId, id);
      if (!ctx) throw AppError.notFound('PLAN_EXERCISE_NOT_FOUND', 'No such plan exercise.');

      const exerciseId = Number.parseInt(req.body?.exerciseId, 10);
      if (!Number.isInteger(exerciseId)) {
        throw AppError.badRequest('EXERCISE_REQUIRED', 'exerciseId is required.');
      }

      // swapPlanExercise throws AppError.badRequest('EXERCISE_NOT_ALLOWED')
      // itself -- the same way src/db/plans.js and src/db/users.js signal
      // expected failures from this layer -- so next(err) carries it to the
      // error handler unchanged. Do not add a translating try/catch here.
      // deps.logger, so a label that fails to record is visible in the server
      // log rather than silently absent from the training data.
      await swapPlanExercise(deps.pool, ctx, exerciseId, { logger: deps.logger });

      res.json({
        data: { plan: withUrls(await getActivePlan(deps.pool, req.user.userId)) },
      });
    } catch (err) { next(err); }
  });

  return router;
};
