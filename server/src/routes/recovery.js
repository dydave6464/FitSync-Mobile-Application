'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  upsertCheckin, todayCheckin, recentCheckins, saveEstimate, latestEstimate,
  CHECKIN_SCALES,
} = require('../db/recovery');
const { readTrainingLoad } = require('../db/training-load');
const { readVolumeBuckets } = require('../db/analytics');

/// The floor the ML stub returns, used when the service cannot be reached.
const FLOOR = { riskLevel: 'low', trainingLoadScore: 0 };

/// Every field present and spelled as its column allows, or a 400 naming the
/// first field that is not. Validated here rather than left to MySQL, which
/// answers an ENUM violation with a 500.
function validateAnswers(body) {
  const answers = {};
  for (const [field, allowed] of Object.entries(CHECKIN_SCALES)) {
    const value = body[field];
    if (!allowed.includes(value)) {
      throw AppError.badRequest(
        'INVALID_CHECKIN',
        `${field} must be one of ${allowed.join(', ')}. Got ${value}.`,
      );
    }
    answers[field] = value;
  }
  return answers;
}

module.exports = function buildRecoveryRouter(deps = {}) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/', auth, async (req, res, next) => {
    try {
      const { userId } = req.user;
      const [checkin, estimate, load] = await Promise.all([
        todayCheckin(deps.pool, userId),
        latestEstimate(deps.pool, userId),
        readVolumeBuckets(deps.pool, userId, 'week'),
      ]);

      res.json({
        data: {
          todayCheckin: checkin,
          latestEstimate: estimate,
          load: load || [],
        },
      });
    } catch (err) { next(err); }
  });

  router.post('/checkin', auth, async (req, res, next) => {
    try {
      const { userId } = req.user;
      const answers = validateAnswers(req.body || {});

      const checkin = await upsertCheckin(deps.pool, userId, answers);
      const [checkins, load] = await Promise.all([
        recentCheckins(deps.pool, userId),
        readTrainingLoad(deps.pool, userId),
      ]);

      let estimate = FLOOR;
      try {
        estimate = await deps.ml.estimateInjuryRisk({
          checkins, load, injuryHistory: [],
        });
      } catch (err) {
        // Logged, not rethrown. The check-in is already stored and is the
        // user's own data; a service being down must not lose it.
        req.log?.warn({ err }, 'injury-risk estimate failed, storing the floor');
      }

      await saveEstimate(deps.pool, {
        userId,
        checkinId: checkin.checkinId,
        riskLevel: estimate.riskLevel,
        trainingLoadScore: estimate.trainingLoadScore,
      });

      res.status(201).json({ data: { checkin, estimate } });
    } catch (err) { next(err); }
  });

  return router;
};
