'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  CONDITIONS, readHealthCheck, writeHealthCheck, deleteHealthCheck,
} = require('../db/health-checks');

/// Not the liveness check in routes/health.js: this is the user's onboarding
/// health check, under /profile because the answers are part of the profile.

const QUESTIONS = ['chestPain', 'dizziness', 'supervisedOnly'];

function invalid(field, message) {
  return AppError.badRequest('INVALID_HEALTH_FIELD', message, [{ field }]);
}

/// The PUT body, checked. Positive means any condition or any Yes; such an
/// answer is stored only when the user both consented and acknowledged the
/// notice. Unknown keys are dropped.
function validate(body) {
  const b = body || {};
  const { conditions } = b;
  if (!Array.isArray(conditions)) {
    throw invalid('conditions', 'conditions must be an array.');
  }
  for (const c of conditions) {
    if (!CONDITIONS.includes(c)) {
      throw invalid('conditions', `conditions must be from: ${CONDITIONS.join(', ')}.`);
    }
  }
  if (new Set(conditions).size !== conditions.length) {
    throw invalid('conditions', 'conditions must not repeat.');
  }
  const answers = {};
  for (const q of QUESTIONS) {
    if (typeof b[q] !== 'boolean') throw invalid(q, `${q} must be true or false.`);
    answers[q] = b[q];
  }
  const positive = conditions.length > 0 || QUESTIONS.some((q) => answers[q]);
  if (positive && b.consent !== true) {
    throw AppError.badRequest(
      'HEALTH_CONSENT_REQUIRED',
      'Health answers that report a condition or a warning sign are stored only with consent.',
    );
  }
  if (positive && b.acknowledged !== true) {
    throw AppError.badRequest(
      'HEALTH_ACK_REQUIRED',
      'The safety notice must be acknowledged before these answers are stored.',
    );
  }
  return { conditions, ...answers, positive };
}

module.exports = function buildHealthCheckRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/profile/health', auth, async (req, res, next) => {
    try {
      res.json({ data: { health: await readHealthCheck(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });

  router.put('/profile/health', auth, async (req, res, next) => {
    try {
      const health = await writeHealthCheck(deps.pool, req.user.userId, validate(req.body));
      res.json({ data: { health } });
    } catch (err) { next(err); }
  });

  router.delete('/profile/health', auth, async (req, res, next) => {
    try {
      await deleteHealthCheck(deps.pool, req.user.userId);
      res.json({ data: { health: null } });
    } catch (err) { next(err); }
  });

  return router;
};
