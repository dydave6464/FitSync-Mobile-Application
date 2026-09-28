'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { manilaDay } = require('../lib/manila-day');
const { dayNumber, dateOf } = require('../lib/streak');
const { saveDay, readWeek } = require('../db/activity');

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_STEPS = 100000;
/// Today and the six days before it: as far back as an iPhone keeps steps.
const DAYS_BACK = 6;

/// A real calendar day inside the window. The round trip is the check:
/// Date.parse rolls 2026-02-30 into March and cannot parse a month 13
/// (routes/calendar.js does the same).
function parseDay(raw) {
  const n = typeof raw === 'string' && DATE.test(raw) ? dayNumber(raw) : NaN;
  if (!Number.isFinite(n) || dateOf(n) !== raw) {
    throw AppError.badRequest('DATE_INVALID', 'date must be a real YYYY-MM-DD day.');
  }
  if (raw < manilaDay(DAYS_BACK) || raw > manilaDay()) {
    throw AppError.badRequest(
      'DATE_OUT_OF_RANGE', 'Steps can be saved for today and the six days before it.',
    );
  }
  return raw;
}

function parseSteps(raw) {
  if (!Number.isInteger(raw) || raw < 0 || raw > MAX_STEPS) {
    throw AppError.badRequest('STEPS_INVALID', `steps must be a whole number from 0 to ${MAX_STEPS}.`);
  }
  return raw;
}

module.exports = function buildActivityRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/', auth, async (req, res, next) => {
    try {
      res.json({ data: await readWeek(deps.pool, req.user.userId, manilaDay()) });
    } catch (err) { next(err); }
  });

  router.put('/:date', auth, async (req, res, next) => {
    try {
      const date = parseDay(req.params.date);
      const steps = parseSteps((req.body || {}).steps);
      res.json({ data: await saveDay(deps.pool, req.user.userId, date, steps) });
    } catch (err) { next(err); }
  });

  return router;
};
