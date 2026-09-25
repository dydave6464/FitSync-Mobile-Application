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

/// Days of check-ins handed to the estimator, and deliberately short.
///
/// risk.py averages the recovery penalty across every check-in it is sent
/// (`sum(penalties) / len(penalties)`), so this window IS the weight today's
/// answers carry. Over the 14 days `recentCheckins` defaults to, a user with
/// a fortnight of good mornings who wakes up wrecked moves their own score by
/// a fourteenth of the penalty -- about four points -- while the tab's "What
/// feeds this score" card and its Update button promise the opposite. Three
/// days gives this morning roughly a third of the term, which is real
/// influence without letting one bad night define the week.
///
/// Widening this back to 14 would quietly dilute the check-in again; it is
/// the estimator's averaging, not the query, that makes the number matter.
const CHECKIN_WINDOW_DAYS = 3;

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
        recentCheckins(deps.pool, userId, CHECKIN_WINDOW_DAYS),
        readTrainingLoad(deps.pool, userId),
      ]);

      // No estimate rather than an invented one when the service is down: a
      // stored 'low' would read on Home as "manageable", indistinguishable
      // from a real estimate. The check-in is already stored -- it is the
      // user's own data -- and the screens fall back to the latest real
      // estimate, captioned with its date.
      let estimate = null;
      try {
        estimate = await deps.ml.estimateInjuryRisk({
          checkins, load, injuryHistory: [],
        });
      } catch (err) {
        req.log?.warn({ err }, 'injury-risk estimate failed; check-in saved without one');
      }

      if (estimate) {
        await saveEstimate(deps.pool, {
          userId,
          checkinId: checkin.checkinId,
          riskLevel: estimate.riskLevel,
          trainingLoadScore: estimate.trainingLoadScore,
        });
      }

      res.status(201).json({ data: { checkin, estimate } });
    } catch (err) { next(err); }
  });

  return router;
};
