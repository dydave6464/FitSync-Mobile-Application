'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  getActivePlan, savePlan, restorePreviousPlan, createPlanFromSession,
  savedPlanForComparison, previousPlanIdForNewPlan,
} = require('../db/plans');
const { getProfile, listInjuries } = require('../db/profile');
const { readRankerHistory } = require('../db/ranker-history');
const { getActiveSession } = require('../db/sessions');
const {
  loadSwapContext, listAlternatives, swapPlanExercise, revertPlanSwap,
} = require('../db/plan-swap');
const { createWeekReaderService } = require('../services/week-reader');
const { cleanReading } = require('../services/week-reader/clean');
const { createReadCache, createDailyLimit } = require('../services/week-reader/memory');

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const MAX_WEEK_TEXT = 300;
const READINGS_PER_DAY = 30;

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

/// True when [generated] has the same exercises on each day as [saved] (a
/// plan's exercises as savedPlanForComparison gives them). Order within a day
/// is ignored: the user would see the same exercises. By id when the
/// generator sent ids, as the ML service does; by name, ignoring case as
/// resolveExerciseIds does, for a generator that sends only names (the stub).
function sameExercises(generated, saved) {
  if (generated.length === 0 || saved.length === 0) return false;
  const byId = generated.every((e) => Number.isInteger(e.exerciseId));
  const keys = (list) => list
    .map((e) => `${e.dayNo || 1}|${byId ? e.exerciseId : String(e.name).toLowerCase()}`)
    .sort();
  const a = keys(generated);
  const b = keys(saved);
  return a.length === b.length && a.every((key, i) => key === b[i]);
}

/// True when [generated] was built from the settings [saved] was: the same
/// split, days, session length and sets x reps. Days never change which
/// exercises are picked, but a user who changed them still changed something.
function sameSettings(generated, saved) {
  const dosage = (list) => [...new Set(list.map((e) => `${e.targetSets}x${e.targetReps}`))]
    .sort().join(',');
  return generated.splitStyle === saved.splitStyle
    && generated.daysPerWeek === saved.daysPerWeek
    && generated.sessionLengthMin === saved.sessionLengthMin
    && dosage(generated.exercises) === dosage(saved.exercises);
}

/// New plan, varied when nothing changed (2026-11-24).
///
/// The generator is deterministic, so with unchanged settings it returns the
/// plan the user already has. When the settings are unchanged and its plan
/// has the same exercises as the current plan, or as the one before it (the
/// user tapping New plan again), it is asked once more with both plans'
/// exercise ids: it moves the current plan's to the back, the previous
/// plan's just ahead of them, and takes each muscle group's next-best -- A,
/// B, C, then A again. It only reorders the exercises its own safety filters
/// already allowed. When any setting changed, the first plan is kept: the
/// user gets the best fit for what they asked.
///
/// The second ask is an improvement, not a requirement: if it fails, the
/// plan already in hand is saved rather than failing the request.
async function generateNewPlan(deps, userId, request, activePlanId) {
  const generated = await deps.ml.generatePlan(request);
  if (activePlanId === null) return generated;
  const current = await savedPlanForComparison(deps.pool, userId, activePlanId);
  if (current === null || !sameSettings(generated, current)) return generated;
  const previousId = await previousPlanIdForNewPlan(deps.pool, userId, activePlanId);
  const previous = previousId === null
    ? [] : (await savedPlanForComparison(deps.pool, userId, previousId)).exercises;
  if (!sameExercises(generated.exercises, current.exercises)
      && !sameExercises(generated.exercises, previous)) {
    return generated;
  }
  const ids = (list) => [...new Set(list.map((e) => e.exerciseId))];
  try {
    return await deps.ml.generatePlan({
      ...request,
      avoid: { current: ids(current.exercises), previous: ids(previous) },
    });
  } catch (err) {
    deps.logger.warn({ err }, 'new plan: the varied ask failed, saving the first plan');
    return generated;
  }
}

/// The refusal both plan-changing routes give while a workout is open. It
/// names that workout, so the app can offer to resume it instead of leaving
/// the user at a message with no way forward. startedAt is null for a legacy
/// row that never recorded one.
function sessionInProgress(open) {
  return AppError.conflict(
    'SESSION_IN_PROGRESS',
    'You have a workout in progress. Finish or discard it before changing your plan.',
    [{ sessionId: open.sessionId, startedAt: open.startedAt }],
  );
}

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

  // Per router, so each app (and each test app) starts with its own.
  const weekReader = deps.weekReader || createWeekReaderService({});
  const readCache = createReadCache();
  const readLimit = createDailyLimit({ perDay: READINGS_PER_DAY });
  // The injury catalogue the reader maps names onto (spec Part 2b step 3:
  // read from the DB, cached). Only seed-injuries.js changes it, before the
  // server starts, so once per router is enough. An empty list is not kept:
  // a catalogue seeded after startup is still picked up.
  let injuryCatalogue = null;
  const readInjuryCatalogue = async () => {
    if (injuryCatalogue === null) {
      const rows = await listInjuries(deps.pool);
      if (rows.length > 0) injuryCatalogue = rows;
      return rows;
    }
    return injuryCatalogue;
  };

  router.get('/active', requireAuth(deps), async (req, res, next) => {
    try {
      // Null rather than 404: "you have no plan yet" is a normal state during
      // onboarding, not a missing resource.
      res.json({
        data: { plan: withUrls(await getActivePlan(deps.pool, req.user.userId)) },
      });
    } catch (err) { next(err); }
  });

  // What "Auto" means for this user right now (spec 2026-11-14, Part 2):
  // ML's own derive(), so the number shown is the number Generate builds.
  router.get('/defaults', requireAuth(deps), async (req, res, next) => {
    try {
      const profile = await getProfile(deps.pool, req.user.userId);
      const { sessionLengthMin, exercisesPerDay, lengthReason } = await deps.ml.planParameters({ ...profile });
      res.json({ data: { sessionLengthMin, exercisesPerDay, lengthReason } });
    } catch (err) { next(err); }
  });

  // "Describe your week" read by Groq (spec 2026-11-14, Part 2b). Never
  // writes the profile or the plan: days and injuries still need the user's
  // own tap in the app.
  router.post('/read-week', requireAuth(deps), async (req, res, next) => {
    try {
      const text = typeof req.body?.text === 'string' ? req.body.text.trim() : '';
      if (text.length < 1 || text.length > MAX_WEEK_TEXT) {
        throw AppError.badRequest('INVALID_WEEK_TEXT',
          `text must be 1 to ${MAX_WEEK_TEXT} characters.`, [{ field: 'text' }]);
      }
      const key = text.toLowerCase().replace(/\s+/g, ' ');
      const cached = readCache.get(key);
      if (cached) return res.json({ data: cached });

      const userId = req.user.userId;
      if (!readLimit.hasRoom(userId)) {
        throw new AppError(429, 'READ_LIMIT', 'AI reading is used up for today.');
      }
      const injuries = await readInjuryCatalogue();
      const raw = await weekReader.read({ text, injuryNames: injuries.map((i) => i.name) });
      const reading = cleanReading(raw, { injuries });
      if (reading === null) {
        throw new AppError(503, 'AI_BUSY', 'AI reading is busy. Try again in a moment.');
      }
      readLimit.count(userId);
      readCache.set(key, reading);
      res.json({ data: reading });
    } catch (err) { next(err); }
  });

  router.post('/regenerate', requireAuth(deps), async (req, res, next) => {
    try {
      const userId = req.user.userId;
      const overrides = validateOverrides(req.body);

      // Replacing the plan under a running workout would strand the logger on
      // exercises no longer in it. Refusing is honest; finish or discard first.
      const open = await getActiveSession(deps.pool, userId);
      if (open) throw sessionInProgress(open);

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
      const history = await readRankerHistory(deps.pool, userId);
      const generated = await generateNewPlan(
        deps, userId, { ...profile, overrides, history }, current === null ? null : current.planId,
      );
      await savePlan(deps.pool, userId, generated);

      res.json({ data: { plan: withUrls(await getActivePlan(deps.pool, userId)) } });
    } catch (err) { next(err); }
  });

  router.post('/restore-previous', requireAuth(deps), async (req, res, next) => {
    try {
      const userId = req.user.userId;
      // As regenerate: swapping the plan under a running workout would strand
      // the logger on exercises no longer in the active plan.
      const open = await getActiveSession(deps.pool, userId);
      if (open) throw sessionInProgress(open);
      await restorePreviousPlan(deps.pool, userId);
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
      const open = await getActiveSession(deps.pool, userId);
      if (open) throw sessionInProgress(open);

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

      // revert: true is the app's Undo: exerciseId is then the exercise to go
      // back to, and the swap being undone must be the slot's latest label.
      const revert = req.body?.revert;
      if (revert !== undefined && typeof revert !== 'boolean') {
        throw invalidPlanField('revert', 'revert must be true or false.');
      }

      // swapPlanExercise throws AppError.badRequest('EXERCISE_NOT_ALLOWED')
      // itself -- the same way src/db/plans.js and src/db/users.js signal
      // expected failures from this layer -- so next(err) carries it to the
      // error handler unchanged. Do not add a translating try/catch here.
      // revertPlanSwap throws its 409 SWAP_NOT_UNDOABLE the same way.
      // deps.logger, so a label that fails to record is visible in the server
      // log rather than silently absent from the training data.
      const { previous } = revert === true
        ? await revertPlanSwap(deps.pool, ctx, exerciseId)
        : await swapPlanExercise(deps.pool, ctx, exerciseId, { logger: deps.logger });

      res.json({
        data: {
          plan: withUrls(await getActivePlan(deps.pool, req.user.userId)),
          // What this call took out of the slot, for the app's Undo.
          previous,
        },
      });
    } catch (err) { next(err); }
  });

  return router;
};
