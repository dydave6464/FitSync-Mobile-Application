'use strict';

/// How far the last 7 days' volume runs ABOVE the user's own weekly baseline,
/// as a percentage of it, where the baseline is the average week over the
/// weeks before this one that the user has trained in, up to 3.
///
/// `InjuryRiskRequest.load` is typed only as a float and is defined nowhere
/// else. risk.py computes `score = load / 2` with moderate at 40 and high at
/// 70, so the number it wants is centred on ZERO: a user training exactly as
/// usual must contribute nothing. A plain ratio does not do that -- 100 would
/// mean "as usual" and already score 50, reporting every healthy user as
/// moderate before a single check-in answer was read. The excess does: 0 is
/// business as usual, 100 is twice the usual week.
///
/// Raw kilograms are not an option either: volume runs to five figures and
/// would pin every user to `high` for ever. The excess over a personal
/// baseline is also the figure that carries the injury signal -- training far
/// more than usual is the risk, not training a lot in absolute terms.
const BASE_RATIO = 100;

/// The largest excess the index reports, chosen so `MAX_LOAD / 2` stays under
/// risk.py's `HIGH_AT` of 70. Volume alone therefore can never reach `high`;
/// it takes a spike AND a bad morning, which is the conservatism the design
/// claims. Raising this to 140 or beyond would hand that claim back: 140 / 2
/// is exactly HIGH_AT, and risk.py's test is `>=`.
const MAX_LOAD = 130;

/// Weeks of history behind the average, at most, not counting the current
/// week.
const BASELINE_WEEKS = 3;

/// How many of the baseline's weeks the user's training history reaches into,
/// from 1 to [BASELINE_WEEKS]. The week blocks run back from the current
/// window: days 7-13, 14-20 and 21-27. A first workout 9 days ago reaches one
/// of them, 16 days ago two, 22 or more all three.
///
/// Always dividing by three made a newcomer's usual week a third of its real
/// size: an ordinary second week read as a 130% spike and the estimate went
/// moderate for simply being new. A user who trained long ago and stopped
/// still counts every week, empty ones included -- coming back hard after a
/// break is the spike the index is for.
function weeksOfHistory(firstDaysAgo) {
  const reached = Math.floor((firstDaysAgo - 7) / 7) + 1;
  return Math.min(Math.max(reached, 1), BASELINE_WEEKS);
}

async function readTrainingLoad(pool, userId) {
  const [[row]] = await pool.query(
    `SELECT
       COALESCE(SUM(CASE WHEN session_date > DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                         THEN total_volume_kg END), 0) AS recent_kg,
       COALESCE(SUM(CASE WHEN session_date <= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                         THEN total_volume_kg END), 0) AS baseline_kg,
       (SELECT DATEDIFF(CURDATE(), MIN(f.session_date))
          FROM workout_sessions f
         WHERE f.user_id = ? AND f.status = 'completed') AS first_days_ago
     FROM workout_sessions
     WHERE user_id = ?
       AND status = 'completed'
       AND session_date > DATE_SUB(CURDATE(), INTERVAL 28 DAY)`,
    [userId, userId],
  );

  const recent = Number(row.recent_kg) || 0;
  const baseline = Number(row.baseline_kg) || 0;

  // No baseline is not "infinitely above baseline". A first week of training
  // is the least informative moment there is, so it scores the same floor the
  // ML stub returns rather than an alarming number.
  if (baseline <= 0) return 0;

  const weeklyAverage =
    baseline / weeksOfHistory(Number(row.first_days_ago) || 0);
  const ratio = (recent / weeklyAverage) * BASE_RATIO;
  // Training less than usual is not negative risk, it is no excess: an easy
  // week floors at 0 rather than pulling the estimate below where a rested
  // user with no history already sits.
  const excess = ratio - BASE_RATIO;

  return Math.round(Math.min(Math.max(excess, 0), MAX_LOAD) * 100) / 100;
}

module.exports = { readTrainingLoad, MAX_LOAD, BASELINE_WEEKS };
