'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  readDay, listHabits, createHabit, updateHabit, deactivateHabit, setCheck,
} = require('../db/routine');

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const notFound = () => AppError.notFound('HABIT_NOT_FOUND', 'No such habit.');

/// The `?date=` query param on a check/uncheck: what the screen believes
/// today is. Absent is fine -- unchanged behaviour, checked against the
/// server's own CURDATE() in `setCheck`. Present and not `YYYY-MM-DD` is a
/// 400, not a silent fall-through to "no date given".
function parseCheckDate(raw) {
  if (raw === undefined) return null;
  if (typeof raw !== 'string' || !DATE.test(raw)) {
    throw AppError.badRequest('DATE_INVALID', 'date must be YYYY-MM-DD.');
  }
  return raw;
}

/// A non-numeric id would reach MySQL as NaN and 500; refuse it as the same
/// 404 a missing habit gets, as routes/sessions.js does for session ids.
function habitIdOr404(raw) {
  const id = Number.parseInt(raw, 10);
  if (!Number.isInteger(id) || String(id) !== String(raw)) throw notFound();
  return id;
}

/// The habit fields in [body], checked. `partial` is PATCH: an absent key is
/// left out of the result so the update leaves it alone, and null is kept
/// for time and durationMin because null means "clear it".
function parseHabit(body, { partial }) {
  const b = body || {};
  const out = {};

  if (!partial || b.title !== undefined) {
    const title = typeof b.title === 'string' ? b.title.trim() : '';
    if (!title) throw AppError.badRequest('TITLE_REQUIRED', 'title is required.');
    if (title.length > 60) {
      throw AppError.badRequest('TITLE_TOO_LONG', 'title must be 60 characters or fewer.');
    }
    out.title = title;
  }
  if (b.time !== undefined) {
    if (b.time !== null && !(typeof b.time === 'string' && TIME.test(b.time))) {
      throw AppError.badRequest('TIME_INVALID', 'time must be HH:MM, 24-hour.');
    }
    out.time = b.time;
  }
  if (b.durationMin !== undefined) {
    const d = b.durationMin;
    if (d !== null && !(Number.isInteger(d) && d >= 1 && d <= 600)) {
      throw AppError.badRequest('DURATION_INVALID', 'durationMin must be a whole number from 1 to 600.');
    }
    out.durationMin = d;
  }
  if (!partial || b.weekdays !== undefined) {
    const w = b.weekdays;
    const valid = Array.isArray(w) && w.length > 0
      && w.every((d) => Number.isInteger(d) && d >= 1 && d <= 7)
      && new Set(w).size === w.length;
    if (!valid) {
      throw AppError.badRequest('WEEKDAYS_INVALID', 'weekdays must list 1-7 at least once, without repeats.');
    }
    out.weekdays = [...w].sort((x, y) => x - y);
  }
  return out;
}

module.exports = function buildRoutineRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/today', auth, async (req, res, next) => {
    try {
      res.json({ data: await readDay(deps.pool, req.user.userId) });
    } catch (err) { next(err); }
  });

  router.get('/habits', auth, async (req, res, next) => {
    try {
      res.json({ data: { habits: await listHabits(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });

  router.post('/habits', auth, async (req, res, next) => {
    try {
      const habit = await createHabit(deps.pool, req.user.userId, parseHabit(req.body, { partial: false }));
      res.status(201).json({ data: { habit } });
    } catch (err) { next(err); }
  });

  router.patch('/habits/:habitId', auth, async (req, res, next) => {
    try {
      const id = habitIdOr404(req.params.habitId);
      const fields = parseHabit(req.body, { partial: true });
      const habit = await updateHabit(deps.pool, req.user.userId, id, fields);
      if (!habit) throw notFound();
      res.json({ data: { habit } });
    } catch (err) { next(err); }
  });

  router.delete('/habits/:habitId', auth, async (req, res, next) => {
    try {
      const id = habitIdOr404(req.params.habitId);
      if (!(await deactivateHabit(deps.pool, req.user.userId, id))) throw notFound();
      res.json({ data: { deleted: true } });
    } catch (err) { next(err); }
  });

  for (const [method, done] of [['put', true], ['delete', false]]) {
    router[method]('/habits/:habitId/check', auth, async (req, res, next) => {
      try {
        const id = habitIdOr404(req.params.habitId);
        const requestedDate = parseCheckDate(req.query.date);
        const result = await setCheck(deps.pool, req.user.userId, id, done, null, requestedDate);
        if (!result) throw notFound();
        res.json({ data: result });
      } catch (err) { next(err); }
    });
  }

  return router;
};
