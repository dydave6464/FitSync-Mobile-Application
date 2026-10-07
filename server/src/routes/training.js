'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { readTrainingSettings, updateTrainingSettings } = require('../db/training-settings');

/// The app's range: 30-second presets up to five minutes, and a custom value
/// from ten seconds to ten minutes. Matches ck_training_settings_rest.
const REST_MIN = 10;
const REST_MAX = 600;

/// The writable fields in [body], checked. Unknown keys are dropped, as
/// PATCH /profile and PATCH /reminders/settings drop them.
function validate(body) {
  const b = body || {};
  const out = {};
  if (b.restSeconds !== undefined) {
    const v = b.restSeconds;
    if (!Number.isInteger(v) || v < REST_MIN || v > REST_MAX) {
      throw AppError.badRequest(
        'REST_INVALID',
        `restSeconds must be a whole number from ${REST_MIN} to ${REST_MAX}.`,
      );
    }
    out.restSeconds = v;
  }
  return out;
}

module.exports = function buildTrainingRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/settings', auth, async (req, res, next) => {
    try {
      res.json({ data: { settings: await readTrainingSettings(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });

  router.patch('/settings', auth, async (req, res, next) => {
    try {
      const settings = await updateTrainingSettings(deps.pool, req.user.userId, validate(req.body));
      res.json({ data: { settings } });
    } catch (err) { next(err); }
  });

  return router;
};
