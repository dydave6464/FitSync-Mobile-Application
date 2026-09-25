'use strict';
const { formatDate, toNumber, periodDays } = require('./sessions');

/// Above this, Epley stops describing anything real -- a 20-rep set says more
/// about conditioning than about a one-rep max.
///
/// Such sets are EXCLUDED rather than clamped. Clamping would invent a number
/// and put it on a chart; excluding says nothing, which is the honest thing to
/// say about a set that does not answer the question.
const MAX_E1RM_REPS = 12;

/// Epley. The standard estimate, and the one Strong and Hevy both chart.
function epley(weightKg, reps) {
  return weightKg * (1 + reps / 30);
}

/// One definition of a set that can carry an e1RM estimate.
const SET_QUALIFIES = `s.status = 'completed'
    AND sl.is_completed = TRUE
    AND sl.weight_kg IS NOT NULL
    AND sl.reps BETWEEN 1 AND ${MAX_E1RM_REPS}`;

/// Only sets that can carry an estimate: completed, loaded, inside the cap,
/// belonging to a finished session.
const QUALIFYING = `
  s.user_id = ? AND ${SET_QUALIFIES}
  AND s.session_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)
`;

/// The exercises worth offering in the picker, most-logged first -- the one
/// with the most data is the one whose chart will look like something.
async function readOptions(pool, userId, period = 'week') {
  // periodDays, not a bare SUMMARY_WINDOWS lookup: indexing reads the
  // prototype chain, so 'constructor' comes back a truthy function, walks
  // past this guard and reaches the query as a bind parameter -- where
  // mysql2 stringifies it and MySQL reads it as a nought-day window,
  // answering 200 with a nonsense series instead of refusing.
  const days = periodDays(period);
  if (!days) return null;

  const [rows] = await pool.query(
    `SELECT sl.exercise_id, e.name, COUNT(*) AS sets
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
       JOIN exercises e ON e.exercise_id = sl.exercise_id
      WHERE ${QUALIFYING}
      GROUP BY sl.exercise_id, e.name
      ORDER BY sets DESC, e.name ASC`,
    [userId, days],
  );

  return rows.map((r) => ({
    exerciseId: r.exercise_id,
    name: r.name,
    sets: Number(r.sets),
  }));
}

/// The e1RM series for one exercise.
///
/// Two shapes, decided here rather than by the client counting points:
///
///   many sessions -> one point per session, x is the date, best set wins
///   one session   -> one point per SET, x is the set number
///
/// The second exists so a user's first workout draws a real line instead of a
/// single dot. It is measured data, not a stand-in -- it shows the
/// within-session fatigue curve, which is worth seeing on its own. The client
/// captions it from `xAxis`, so the two modes never get confused.
///
/// Best set per session rather than last, for the reason `lastPerformance()`
/// already gives: the final set is usually where form broke down.
async function readSeries(pool, userId, exerciseId, period = 'week') {
  // periodDays, not a bare SUMMARY_WINDOWS lookup: indexing reads the
  // prototype chain, so 'constructor' comes back a truthy function, walks
  // past this guard and reaches the query as a bind parameter -- where
  // mysql2 stringifies it and MySQL reads it as a nought-day window,
  // answering 200 with a nonsense series instead of refusing.
  const days = periodDays(period);
  if (!days) return null;

  const [rows] = await pool.query(
    `SELECT sl.set_number, sl.weight_kg, sl.reps, s.session_id, s.session_date
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
      WHERE ${QUALIFYING} AND sl.exercise_id = ?
      ORDER BY s.session_date ASC, sl.set_number ASC`,
    [userId, days, exerciseId],
  );

  if (rows.length === 0) return { xAxis: 'date', points: [] };

  const sessions = new Set(rows.map((r) => r.session_id));

  if (sessions.size === 1) {
    return {
      xAxis: 'set',
      points: rows.map((r) => ({
        label: String(r.set_number),
        e1rmKg: round1(epley(toNumber(r.weight_kg), r.reps)),
      })),
    };
  }

  // Keyed on session_id, not on the formatted date: two completed sessions can
  // share a calendar day (an AM/PM split, a corrected re-log), and nothing in
  // the app forbids it. Keying on the date string would collide them into one
  // map entry and silently drop whichever session lost the max() comparison.
  // Two same-day points sharing one date label is correct -- the x-axis is a
  // sequential index and the label is only text.
  const best = new Map(); // session_id -> { label, value }
  for (const row of rows) {
    const value = epley(toNumber(row.weight_kg), row.reps);
    const current = best.get(row.session_id);
    if (!current || value > current.value) {
      best.set(row.session_id, { label: formatDate(row.session_date), value });
    }
  }

  return {
    xAxis: 'date',
    points: [...best.values()].map(({ label, value }) => ({
      label,
      e1rmKg: round1(value),
    })),
  };
}

/// Epley in SQL, for aggregating across every set at once. Must stay the same
/// formula as epley() above.
const E1RM_SQL = 'sl.weight_kg * (1 + sl.reps / 30)';

/// How many exercises set a new best estimated 1RM in the last [days] days.
///
/// Per exercise: the best e1RM inside the window against the best from before
/// it. Strictly greater counts; a tie does not. An exercise first logged inside
/// the window has no earlier best, and NULL compares as unknown, so it drops
/// out -- a new account's first month is not a string of "PRs".
///
/// The window is the N calendar days ending today (`>` CURDATE() - N), the
/// same edge summariseHistory and the charts use, since the count is reported
/// inside that summary; everything on or before CURDATE() - N is earlier
/// history.
async function countNewPrs(pool, userId, days) {
  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS n
       FROM (
         SELECT sl.exercise_id,
                MAX(CASE WHEN s.session_date >  DATE_SUB(CURDATE(), INTERVAL ? DAY)
                         THEN ${E1RM_SQL} END) AS window_best,
                MAX(CASE WHEN s.session_date <= DATE_SUB(CURDATE(), INTERVAL ? DAY)
                         THEN ${E1RM_SQL} END) AS earlier_best
           FROM set_logs sl
           JOIN workout_sessions s ON s.session_id = sl.session_id
          WHERE s.user_id = ? AND ${SET_QUALIFIES}
          GROUP BY sl.exercise_id
       ) per_exercise
      WHERE window_best > earlier_best`,
    [days, days, userId],
  );
  return Number(row.n);
}

/// One decimal. An estimate carrying six of them claims a precision it does
/// not have.
function round1(value) {
  return Math.round(value * 10) / 10;
}

module.exports = { epley, readOptions, readSeries, countNewPrs, MAX_E1RM_REPS };
