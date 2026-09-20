'use strict';

/// The last 7 days' volume as a percentage of the trailing 4-week weekly
/// average.
///
/// `InjuryRiskRequest.load` is typed only as a float and is defined nowhere
/// else. risk.py computes `score = load / 2` with moderate at 40 and high at
/// 70, so it wants roughly 0-140 -- raw kilograms run to five figures and
/// would pin every user to `high` for ever. A ratio is also the figure that
/// actually carries injury signal: training far more than usual is the risk,
/// not training a lot in absolute terms.
const MAX_LOAD = 140;

/// Weeks of history behind the average, not counting the current week.
const BASELINE_WEEKS = 3;

async function readTrainingLoad(pool, userId) {
  const [[row]] = await pool.query(
    `SELECT
       COALESCE(SUM(CASE WHEN session_date > DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                         THEN total_volume_kg END), 0) AS recent_kg,
       COALESCE(SUM(CASE WHEN session_date <= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                         THEN total_volume_kg END), 0) AS baseline_kg
     FROM workout_sessions
     WHERE user_id = ?
       AND status = 'completed'
       AND session_date > DATE_SUB(CURDATE(), INTERVAL 28 DAY)`,
    [userId],
  );

  const recent = Number(row.recent_kg) || 0;
  const baseline = Number(row.baseline_kg) || 0;

  // No baseline is not "infinitely above baseline". A first week of training
  // is the least informative moment there is, so it scores the same floor the
  // ML stub returns rather than an alarming number.
  if (baseline <= 0) return 0;

  const weeklyAverage = baseline / BASELINE_WEEKS;
  const ratio = (recent / weeklyAverage) * 100;

  return Math.round(Math.min(Math.max(ratio, 0), MAX_LOAD) * 100) / 100;
}

module.exports = { readTrainingLoad, MAX_LOAD, BASELINE_WEEKS };
