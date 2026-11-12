'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  upsertCheckin, todayCheckin, recentCheckins, saveEstimate, latestEstimate,
  reportedInjuries, worstRecentPain, CHECKIN_SCALES,
} = require('../db/recovery');
const { PAIN_LEVELS } = require('../db/session-outcomes');
const { readTrainingLoad } = require('../db/training-load');
const { readVolumeBuckets } = require('../db/analytics');
const { readMuscleRecency } = require('../db/muscle-recency');

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

const RISK_LEVELS = ['low', 'moderate', 'high'];
const SOURCES = ['model', 'rules'];

/// The most drivers the tab explains. The service is asked for at most three;
/// this holds a service that sends more to the same promise.
const MAX_DRIVERS = 3;

/// Each driver key the ML contract defines, and the values that could have
/// been one. Each answer list is a subset of the scale the check-in was
/// validated with, so a driver can only ever quote something the user could
/// have said.
///
/// The contract's bar is 5 rule points or more (the amendment of 2026-10-18),
/// and these are the values that reach it: a load of 10% or more, a poor or
/// fair night, moderate or severe soreness, low or very low energy, moderate
/// or high stress, any reported injury, and any recent pain. Everyday answers
/// never are, so a service that slips one through cannot make an ordinary
/// morning read as a reason; the tab says "Nothing ... stands out" instead.
const DRIVER_VALUES = Object.freeze({
  load: (v) => Number.isFinite(v) && v >= 10,
  sleep: (v) => ['poor', 'fair'].includes(v),
  soreness: (v) => ['moderate', 'severe'].includes(v),
  energy: (v) => ['very_low', 'low'].includes(v),
  stress: (v) => ['moderate', 'high'].includes(v),
  injury_history: (v) => Number.isInteger(v) && v >= 1,
  recent_pain: (v) => PAIN_LEVELS.includes(v) && v !== 'none',
});

/// The largest load_pct the DECIMAL(5,2) column holds. MySQL rounds to two
/// places before it range-checks, so 999.995 becomes 1000.00 and fails the
/// INSERT, and with it the check-in. The value is rounded here first and the
/// rounded value is what is checked, stored and returned.
const MAX_LOAD_PCT = 999.99;

/// loadPct rounded as the column will hold it, or null when the column
/// cannot hold it.
function toLoadPct(value) {
  if (!Number.isFinite(value) || value < 0) return null;
  // Rounded through its decimal text rather than Math.round(value * 100),
  // which misreads values whose binary form sits just below the half (1.005
  // becomes 1.00); the driver sends MySQL that same text and it rounds it
  // half up.
  // Text already in exponent form is a value far below a cent (or far beyond
  // the column), where plain arithmetic gives the same answer.
  const text = String(value);
  const rounded = text.includes('e')
    ? Math.round(value * 100) / 100
    : Number(`${Math.round(Number(`${text}e2`))}e-2`);
  return Number.isFinite(rounded) && rounded <= MAX_LOAD_PCT ? rounded : null;
}

/// The drivers worth storing: known keys whose values could have reached the
/// 5-point driver bar, in the service's order, at most MAX_DRIVERS. Anything
/// else is dropped one entry at a time rather than failing the estimate -- a
/// driver is the explanation, and a bad one should cost its line on the tab,
/// not the level above it. Absent
/// altogether (a service from before drivers existed), or not a list, is null
/// and stored as NULL, like an estimate from before migration 037.
function toDrivers(raw) {
  if (!Array.isArray(raw)) return null;
  return raw
    .filter((d) => d && typeof d === 'object'
      && Object.hasOwn(DRIVER_VALUES, d.key) && DRIVER_VALUES[d.key](d.value))
    .slice(0, MAX_DRIVERS)
    .map((d) => ({ key: d.key, value: d.value }));
}

/// The ML service's answer as something safe to store, or null when it is
/// not an estimate at all.
///
/// The level and score are what Home and the tab show, so an answer without a
/// known level, or with a score outside 0-100, is no estimate: it is skipped,
/// exactly as when the service is down, rather than stored and shown. The
/// explanation fields are optional extras and are coerced instead -- an
/// unknown source or a load the column cannot hold becomes null -- so a slip
/// there never costs the user their estimate.
function toEstimate(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  if (!RISK_LEVELS.includes(raw.riskLevel)) return null;

  const score = raw.trainingLoadScore ?? null;
  if (score !== null && !(Number.isFinite(score) && score >= 0 && score <= 100)) {
    return null;
  }

  // load_pct is DECIMAL(5,2): anything outside it would fail the INSERT and,
  // with it, the request.
  const loadPct = toLoadPct(raw.loadPct);
  const modelVersion = typeof raw.modelVersion === 'string'
    && raw.modelVersion.length > 0 && raw.modelVersion.length <= 40
    ? raw.modelVersion
    : null;

  return {
    riskLevel: raw.riskLevel,
    trainingLoadScore: score,
    source: SOURCES.includes(raw.source) ? raw.source : null,
    modelVersion,
    loadPct,
    drivers: toDrivers(raw.drivers),
  };
}

/// What a refused answer looked like, for the log: its key fields and the
/// driver keys, never the driver values, which quote the user's own answers.
/// Strings are clipped so a broken service cannot flood the log.
function summarizeAnswer(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return { type: Array.isArray(raw) ? 'array' : raw === null ? 'null' : typeof raw };
  }
  const clip = (v) => (typeof v === 'string' ? v.slice(0, 40) : v);
  const scalar = (v) => (v === null || ['string', 'number', 'boolean'].includes(typeof v)
    ? clip(v)
    : typeof v);
  return {
    riskLevel: scalar(raw.riskLevel ?? null),
    trainingLoadScore: scalar(raw.trainingLoadScore ?? null),
    source: scalar(raw.source ?? null),
    loadPct: scalar(raw.loadPct ?? null),
    driverKeys: Array.isArray(raw.drivers)
      ? raw.drivers.slice(0, 10).map((d) => (d && typeof d === 'object' ? scalar(d.key ?? null) : typeof d))
      : scalar(raw.drivers ?? null),
  };
}

const NO_CHECKIN_TODAY =
  "There's no check-in for today yet. Check in first to get today's estimate.";
const ESTIMATE_UNAVAILABLE =
  "Couldn't work out your estimate right now. Your check-in is saved, so try again in a few minutes.";

/// Estimates today's risk for [checkin] and stores it, answering the stored
/// estimate in the shape the app reads, or null when there is none to give.
/// POST /checkin and POST /estimate both come through here, so the two can
/// never send the service different inputs or describe the result
/// differently.
///
/// No estimate rather than an invented one when the service is down: a
/// stored 'low' would read on Home as "manageable", indistinguishable from a
/// real estimate. The check-in is already stored -- it is the user's own
/// data -- and the screens fall back to the latest real estimate, captioned
/// with its date. A malformed answer is treated the same way: toEstimate
/// refuses it, and the check-in stands without an estimate.
async function computeEstimate(deps, req, userId, checkin) {
  const [checkins, load, injuryHistory, recentPain] = await Promise.all([
    recentCheckins(deps.pool, userId, CHECKIN_WINDOW_DAYS),
    readTrainingLoad(deps.pool, userId),
    reportedInjuries(deps.pool, userId),
    worstRecentPain(deps.pool, userId),
  ]);

  let estimate = null;
  try {
    const raw = await deps.ml.estimateInjuryRisk({
      checkins, load, injuryHistory, recentPain,
    });
    estimate = toEstimate(raw);
    if (!estimate) {
      req.log?.warn(
        { mlAnswer: summarizeAnswer(raw) },
        'injury-risk estimate malformed; check-in saved without one',
      );
    }
  } catch (err) {
    req.log?.warn({ err }, 'injury-risk estimate failed; check-in saved without one');
  }
  if (!estimate) return null;

  await saveEstimate(deps.pool, {
    userId, checkinId: checkin.checkinId, ...estimate,
  });

  // drivers is stored as NULL for an answer without a list, which GET then
  // reads as []. The answer says [] too, so the screen that just asked and
  // the tab it opens next describe the same row the same way; the client
  // tells "predates drivers" apart by source, not by drivers. checkinDate is
  // the date GET's latestEstimate carries, so the app can tell today's
  // estimate from an older one without refetching the tab.
  return {
    riskLevel: estimate.riskLevel,
    trainingLoadScore: estimate.trainingLoadScore,
    checkinDate: checkin.checkinDate,
    source: estimate.source,
    modelVersion: estimate.modelVersion,
    loadPct: estimate.loadPct,
    drivers: estimate.drivers ?? [],
  };
}

module.exports = function buildRecoveryRouter(deps = {}) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/', auth, async (req, res, next) => {
    try {
      const { userId } = req.user;
      const [checkin, estimate, load, muscles, inWindow] = await Promise.all([
        todayCheckin(deps.pool, userId),
        latestEstimate(deps.pool, userId),
        readVolumeBuckets(deps.pool, userId, 'week'),
        readMuscleRecency(deps.pool, userId),
        recentCheckins(deps.pool, userId, CHECKIN_WINDOW_DAYS),
      ]);

      res.json({
        data: {
          todayCheckin: checkin,
          latestEstimate: estimate,
          // How many check-ins today's estimate rests on: the same window the
          // estimator is sent, so the tab can say when that is very few.
          checkinCount: inWindow.length,
          load: load || [],
          muscles,
        },
      });
    } catch (err) { next(err); }
  });

  router.post('/checkin', auth, async (req, res, next) => {
    try {
      const { userId } = req.user;
      const answers = validateAnswers(req.body || {});

      const checkin = await upsertCheckin(deps.pool, userId, answers);
      const estimate = await computeEstimate(deps, req, userId, checkin);
      res.status(201).json({ data: { checkin, estimate } });
    } catch (err) { next(err); }
  });

  /// Today's estimate again, for the morning the service was down (or sent
  /// something unusable) when the user checked in. The stored check-in is
  /// re-estimated as it stands; the body is ignored, and the check-in is not
  /// rewritten.
  ///
  /// A check-in that already has an estimate gets that one back (200) without
  /// asking the service again, so a double tap, or a retry racing another
  /// phone, does not append a duplicate. Two retries at the very same moment
  /// can still both store one; that is harmless, since the table is
  /// append-only and the newest is the one shown.
  ///
  /// An explicit POST rather than a retry inside GET: GET runs on every tab
  /// open and Home refresh, and should neither wait on the ML service nor
  /// write.
  router.post('/estimate', auth, async (req, res, next) => {
    try {
      const { userId } = req.user;
      const checkin = await todayCheckin(deps.pool, userId);
      if (!checkin) throw AppError.conflict('NO_CHECKIN_TODAY', NO_CHECKIN_TODAY);

      const latest = await latestEstimate(deps.pool, userId);
      if (latest && latest.checkinDate === checkin.checkinDate) {
        res.json({ data: { estimate: latest } });
        return;
      }

      const estimate = await computeEstimate(deps, req, userId, checkin);
      if (!estimate) throw new AppError(502, 'ESTIMATE_UNAVAILABLE', ESTIMATE_UNAVAILABLE);
      res.status(201).json({ data: { estimate } });
    } catch (err) { next(err); }
  });

  return router;
};
