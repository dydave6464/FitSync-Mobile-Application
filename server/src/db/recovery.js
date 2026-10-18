'use strict';
const { formatDate } = require('./sessions');
const { PAIN_LEVELS } = require('./session-outcomes');

/// How far back a pain report still counts toward today's estimate: the last
/// 14 days, today included, by the date of the session it was reported about.
///
/// Wider than OUTCOME_WINDOW_DAYS (7), which only decides which session the
/// app asks about. A strained knee two weeks ago is still worth training
/// around; much beyond that, an injury the user still has belongs in their
/// profile's reported injuries, which the estimate reads separately.
const RECENT_PAIN_DAYS = 14;

/// The allowed values per field, in worst-to-best order.
///
/// Spelled exactly as the ENUMs in migration 003 AND exactly as the keys in
/// ml/app/risk.py's SLEEP/SORENESS/ENERGY/STRESS maps. Those maps are read
/// with `.get(value, 0.0)`, so a divergence here would not raise -- it would
/// quietly score every user as lower risk than they are.
const CHECKIN_SCALES = Object.freeze({
  sleepQuality: ['poor', 'fair', 'good', 'excellent'],
  muscleSoreness: ['none', 'mild', 'moderate', 'severe'],
  energy: ['very_low', 'low', 'moderate', 'high'],
  stress: ['very_low', 'low', 'moderate', 'high'],
});

function toCheckin(row) {
  return {
    checkinId: row.checkin_id,
    checkinDate: formatDate(row.checkin_date),
    sleepQuality: row.sleep_quality,
    muscleSoreness: row.muscle_soreness,
    energy: row.energy,
    stress: row.stress,
  };
}

/// Today's check-in, created or replaced.
///
/// ON DUPLICATE KEY rather than a read-then-write: uq_morning_checkins_user_date
/// already enforces one row per day, so letting MySQL resolve the collision is
/// both shorter and free of the race between two taps of Update.
async function upsertCheckin(pool, userId, answers) {
  await pool.query(
    `INSERT INTO morning_checkins
       (user_id, checkin_date, sleep_quality, muscle_soreness, energy, stress)
     VALUES (?, CURDATE(), ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       sleep_quality = VALUES(sleep_quality),
       muscle_soreness = VALUES(muscle_soreness),
       energy = VALUES(energy),
       stress = VALUES(stress)`,
    [userId, answers.sleepQuality, answers.muscleSoreness, answers.energy, answers.stress],
  );

  // Read back rather than trusting insertId: on the update branch insertId is
  // not the existing row's id, and callers need the real one for the estimate's
  // foreign key.
  return todayCheckin(pool, userId);
}

async function todayCheckin(pool, userId) {
  const [[row]] = await pool.query(
    `SELECT checkin_id, checkin_date, sleep_quality, muscle_soreness, energy, stress
       FROM morning_checkins
      WHERE user_id = ? AND checkin_date = CURDATE()`,
    [userId],
  );
  return row ? toCheckin(row) : null;
}

/// The window handed to the ML service, newest first.
async function recentCheckins(pool, userId, days = 14) {
  const [rows] = await pool.query(
    `SELECT checkin_id, checkin_date, sleep_quality, muscle_soreness, energy, stress
       FROM morning_checkins
      WHERE user_id = ?
        AND checkin_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)
      ORDER BY checkin_date DESC`,
    [userId, days],
  );
  return rows.map(toCheckin);
}

/// The user's reported injuries, in the {injuryId, regionGroup} shape the
/// plan payload sends -- the same rows getProfile reads, without the rest of
/// the profile the estimate has no use for.
async function reportedInjuries(pool, userId) {
  const [rows] = await pool.query(
    `SELECT i.injury_id, i.region_group
       FROM user_injuries ui
       JOIN injuries i ON i.injury_id = ui.injury_id
      WHERE ui.user_id = ? ORDER BY i.injury_id`,
    [userId],
  );
  return rows.map((r) => ({ injuryId: r.injury_id, regionGroup: r.region_group }));
}

/// The worst pain level reported about any session dated in the last
/// RECENT_PAIN_DAYS days, or null when there are no reports at all.
///
/// 'none' is a real answer and comes back as 'none': session_outcomes keeps
/// "nothing hurt" and "never answered" apart (migration 021), and so does
/// this. Sessions dated after today are excluded so a clock or data error
/// cannot widen the window forward.
async function worstRecentPain(pool, userId, days = RECENT_PAIN_DAYS) {
  const [[row]] = await pool.query(
    `SELECT o.pain_level
       FROM session_outcomes o
       JOIN workout_sessions s ON s.session_id = o.session_id
      WHERE o.user_id = ? AND s.user_id = ?
        AND s.session_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)
        AND s.session_date <= CURDATE()
      ORDER BY FIELD(o.pain_level, ?) DESC
      LIMIT 1`,
    [userId, userId, days, PAIN_LEVELS],
  );
  return row ? row.pain_level : null;
}

/// Append-only: an updated check-in writes another estimate rather than
/// editing the last, so the history stays a record of what was estimated when.
///
/// source, modelVersion, loadPct and drivers are optional so a caller with
/// only a level and score still writes a valid row; anything left out is
/// stored as NULL, which reads back exactly like an estimate from before 037.
async function saveEstimate(pool, {
  userId, checkinId, riskLevel, trainingLoadScore,
  source = null, modelVersion = null, loadPct = null, drivers = null,
}) {
  await pool.query(
    `INSERT INTO injury_risk_estimates
       (user_id, checkin_id, risk_level, training_load_score,
        source, model_version, load_pct, drivers)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      userId, checkinId, riskLevel, trainingLoadScore,
      source, modelVersion, loadPct,
      drivers === null ? null : JSON.stringify(drivers),
    ],
  );
}

/// The drivers column as a list. mysql2 hands a JSON column back already
/// parsed, but a string is parsed here too in case a driver or server
/// returns the raw text; NULL (an estimate from before 037) reads as [].
function toDrivers(value) {
  if (value === null || value === undefined) return [];
  const parsed = typeof value === 'string' ? JSON.parse(value) : value;
  return Array.isArray(parsed) ? parsed : [];
}

async function latestEstimate(pool, userId) {
  const [[row]] = await pool.query(
    `SELECT e.risk_level, e.training_load_score, e.source, e.load_pct, e.drivers,
            c.checkin_date
       FROM injury_risk_estimates e
       JOIN morning_checkins c ON c.checkin_id = e.checkin_id
      WHERE e.user_id = ?
      ORDER BY e.computed_at DESC, e.estimate_id DESC
      LIMIT 1`,
    [userId],
  );
  if (!row) return null;

  return {
    riskLevel: row.risk_level,
    trainingLoadScore: row.training_load_score === null
      ? null
      : Number(row.training_load_score),
    checkinDate: formatDate(row.checkin_date),
    source: row.source ?? null,
    loadPct: row.load_pct === null ? null : Number(row.load_pct),
    drivers: toDrivers(row.drivers),
  };
}

module.exports = {
  upsertCheckin,
  todayCheckin,
  recentCheckins,
  saveEstimate,
  latestEstimate,
  reportedInjuries,
  worstRecentPain,
  CHECKIN_SCALES,
  RECENT_PAIN_DAYS,
};
