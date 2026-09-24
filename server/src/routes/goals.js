'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  listGoals, deleteGoal, bestKg, isLiveExercise, listOptions, createGoalIfNoneOpen,
} = require('../db/goals');

const notFound = () => AppError.notFound('GOAL_NOT_FOUND', 'No such goal.');

/// A non-numeric id would reach MySQL as NaN; refuse it as the same 404 a
/// missing goal gets, as routes/routine.js does for habit ids.
function goalIdOr404(raw) {
  const id = Number.parseInt(raw, 10);
  if (!Number.isInteger(id) || String(id) !== String(raw)) throw notFound();
  return id;
}

/// Kilograms as the app writes them: 52.5, not 52.50.
function kg(value) {
  return String(Number(value.toFixed(2)));
}

module.exports = function buildGoalsRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/', auth, async (req, res, next) => {
    try {
      res.json({ data: { goals: await listGoals(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });

  router.get('/options', auth, async (req, res, next) => {
    try {
      res.json({ data: { options: await listOptions(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });

  router.post('/', auth, async (req, res, next) => {
    try {
      const { userId } = req.user;
      const { exerciseId, targetKg } = req.body || {};
      if (!Number.isInteger(exerciseId) || !(await isLiveExercise(deps.pool, exerciseId))) {
        throw AppError.badRequest('EXERCISE_INVALID', 'Choose an exercise from the catalogue.');
      }
      if (typeof targetKg !== 'number' || !Number.isFinite(targetKg)
          || targetKg < 0.5 || targetKg > 999.99) {
        throw AppError.badRequest('TARGET_INVALID', 'targetKg must be a number from 0.5 to 999.99.');
      }
      const target = Math.round(targetKg * 100) / 100;

      // A goal already met means nothing on the screen.
      const best = await bestKg(deps.pool, userId, exerciseId);
      if (best !== null && target <= best) {
        throw AppError.badRequest('GOAL_ALREADY_MET', `Your best is already ${kg(best)} kg.`);
      }

      const goal = await createGoalIfNoneOpen(deps.pool, userId, exerciseId, target);
      if (goal === null) {
        throw AppError.conflict('GOAL_EXISTS', 'You already have a goal for this exercise.');
      }
      res.status(201).json({ data: { goal } });
    } catch (err) { next(err); }
  });

  router.delete('/:goalId', auth, async (req, res, next) => {
    try {
      const id = goalIdOr404(req.params.goalId);
      if (!(await deleteGoal(deps.pool, req.user.userId, id))) throw notFound();
      res.json({ data: { deleted: true } });
    } catch (err) { next(err); }
  });

  return router;
};
