'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { readCalendar } = require('../db/calendar');
const { dayNumber, dateOf } = require('../lib/streak');

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_DAYS = 62;

/// The day number of a real calendar date in YYYY-MM-DD, or null. The round
/// trip is the check: Date.parse rolls 2026-02-30 into March, so it comes
/// back as a different string, and a month 13 does not parse at all.
function dayOf(raw) {
  if (typeof raw !== 'string' || !DATE.test(raw)) return null;
  const n = dayNumber(raw);
  return Number.isFinite(n) && dateOf(n) === raw ? n : null;
}

/// `?from&to`: both real dates, from on or before to, at most 62 days
/// inclusive -- enough for a six-week month grid.
function parseRange(query) {
  const from = dayOf(query.from);
  const to = dayOf(query.to);
  if (from === null || to === null || from > to || to - from + 1 > MAX_DAYS) {
    throw AppError.badRequest(
      'DATE_RANGE_INVALID',
      `from and to must be real dates (YYYY-MM-DD), from on or before to, at most ${MAX_DAYS} days.`,
    );
  }
  return { from: query.from, to: query.to };
}

module.exports = function buildCalendarRouter(deps) {
  const router = express.Router();

  router.get('/', requireAuth(deps), async (req, res, next) => {
    try {
      const { from, to } = parseRange(req.query);
      res.json({ data: await readCalendar(deps.pool, req.user.userId, from, to) });
    } catch (err) { next(err); }
  });

  return router;
};
