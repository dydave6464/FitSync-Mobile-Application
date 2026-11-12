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
const MAX_BATCH_DAYS = DAYS_BACK + 1;

/// A real calendar day, or a 400. The round trip is the check: Date.parse
/// rolls 2026-02-30 into March and cannot parse a month 13
/// (routes/calendar.js does the same).
function parseDay(raw) {
  const n = typeof raw === 'string' && DATE.test(raw) ? dayNumber(raw) : NaN;
  if (!Number.isFinite(n) || dateOf(n) !== raw) {
    throw AppError.badRequest('DATE_INVALID', 'date must be a real YYYY-MM-DD day.');
  }
  return raw;
}

/// Whether [day] is today or one of the six days before it, in Manila.
function inWindow(day) {
  return day >= manilaDay(DAYS_BACK) && day <= manilaDay();
}

function parseSteps(raw) {
  if (!Number.isInteger(raw) || raw < 0 || raw > MAX_STEPS) {
    throw AppError.badRequest('STEPS_INVALID', `steps must be a whole number from 0 to ${MAX_STEPS}.`);
  }
  return raw;
}

/// The batch body as [{ date, steps }], checked whole before anything is
/// saved, so a 400 saves nothing.
function parseBatch(body) {
  const days = (body || {}).days;
  if (!Array.isArray(days) || days.length < 1 || days.length > MAX_BATCH_DAYS
    || days.some((d) => !d || typeof d !== 'object' || Array.isArray(d))) {
    throw AppError.badRequest(
      'DAYS_INVALID', `days must be a list of 1 to ${MAX_BATCH_DAYS} { date, steps } entries.`,
    );
  }
  const seen = new Set();
  return days.map((d) => {
    const date = parseDay(d.date);
    const steps = parseSteps(d.steps);
    if (seen.has(date)) {
      throw AppError.badRequest('DAYS_INVALID', 'Each day can be sent only once.');
    }
    seen.add(date);
    return { date, steps };
  });
}

module.exports = function buildActivityRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/', auth, async (req, res, next) => {
    try {
      res.json({ data: await readWeek(deps.pool, req.user.userId, manilaDay()) });
    } catch (err) { next(err); }
  });

  /// Several days in one request -- the phone's week on each sync -- answered
  /// with the week as GET answers it, plus `skipped`.
  ///
  /// One rule differs from PUT /:date: a date outside today and the six days
  /// before it is not an error here. It is skipped and listed in `skipped`,
  /// in the order sent, so a phone whose clock is off does not lose the days
  /// that are in range. Everything else is validated for the whole body
  /// first, and a 400 saves nothing.
  ///
  /// The kept days are saved oldest first, one after another rather than all
  /// at once: one connection at a time, and the same lock order on every
  /// request. saveDay keeps the higher count, so resending a day is harmless.
  router.put('/', auth, async (req, res, next) => {
    try {
      const { userId } = req.user;
      const days = parseBatch(req.body);
      const kept = days.filter((d) => inWindow(d.date))
        .sort((a, b) => (a.date < b.date ? -1 : 1));
      const skipped = days.filter((d) => !inWindow(d.date)).map((d) => d.date);
      for (const { date, steps } of kept) {
        await saveDay(deps.pool, userId, date, steps);
      }
      res.json({ data: { ...(await readWeek(deps.pool, userId, manilaDay())), skipped } });
    } catch (err) { next(err); }
  });

  router.put('/:date', auth, async (req, res, next) => {
    try {
      const date = parseDay(req.params.date);
      if (!inWindow(date)) {
        throw AppError.badRequest(
          'DATE_OUT_OF_RANGE', 'Steps can be saved for today and the six days before it.',
        );
      }
      const steps = parseSteps((req.body || {}).steps);
      res.json({ data: await saveDay(deps.pool, req.user.userId, date, steps) });
    } catch (err) { next(err); }
  });

  return router;
};
