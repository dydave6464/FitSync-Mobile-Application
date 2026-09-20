'use strict';
const { formatDate } = require('./sessions');

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

/// Append-only: an updated check-in writes another estimate rather than
/// editing the last, so the history stays a record of what was estimated when.
async function saveEstimate(pool, { userId, checkinId, riskLevel, trainingLoadScore }) {
  await pool.query(
    `INSERT INTO injury_risk_estimates
       (user_id, checkin_id, risk_level, training_load_score)
     VALUES (?, ?, ?, ?)`,
    [userId, checkinId, riskLevel, trainingLoadScore],
  );
}

async function latestEstimate(pool, userId) {
  const [[row]] = await pool.query(
    `SELECT e.risk_level, e.training_load_score, c.checkin_date
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
  };
}

module.exports = {
  upsertCheckin,
  todayCheckin,
  recentCheckins,
  saveEstimate,
  latestEstimate,
  CHECKIN_SCALES,
};
