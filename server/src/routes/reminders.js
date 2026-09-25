'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { readReminderSettings, updateReminderSettings } = require('../db/reminders');

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const LEADS = [0, 5, 15, 30];
const BOOLEANS = ['habitsEnabled', 'workoutEnabled', 'checkinEnabled'];
const TIMES = ['workoutTime', 'checkinTime'];

/// The writable fields in [body], checked. Unknown keys are dropped, as
/// PATCH /profile drops them (routes/profile.js).
function validate(body) {
  const b = body || {};
  const out = {};
  for (const key of BOOLEANS) {
    if (b[key] === undefined) continue;
    if (typeof b[key] !== 'boolean') {
      throw AppError.badRequest('REMINDER_INVALID', `${key} must be true or false.`);
    }
    out[key] = b[key];
  }
  if (b.habitLeadMin !== undefined) {
    if (!LEADS.includes(b.habitLeadMin)) {
      throw AppError.badRequest('LEAD_INVALID', 'habitLeadMin must be 0, 5, 15 or 30.');
    }
    out.habitLeadMin = b.habitLeadMin;
  }
  for (const key of TIMES) {
    if (b[key] === undefined) continue;
    if (typeof b[key] !== 'string' || !TIME.test(b[key])) {
      throw AppError.badRequest('TIME_INVALID', `${key} must be HH:MM, 24-hour.`);
    }
    out[key] = b[key];
  }
  return out;
}

module.exports = function buildRemindersRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/settings', auth, async (req, res, next) => {
    try {
      res.json({ data: { settings: await readReminderSettings(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });

  router.patch('/settings', auth, async (req, res, next) => {
    try {
      const settings = await updateReminderSettings(deps.pool, req.user.userId, validate(req.body));
      res.json({ data: { settings } });
    } catch (err) { next(err); }
  });

  return router;
};
