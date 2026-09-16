'use strict';
const { formatDate, toNumber, SUMMARY_WINDOWS } = require('./sessions');

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

/// Only sets that can carry an estimate: completed, loaded, inside the cap,
/// belonging to a finished session.
const QUALIFYING = `
  s.user_id = ? AND s.status = 'completed'
  AND sl.is_completed = TRUE
  AND sl.weight_kg IS NOT NULL
  AND sl.reps BETWEEN 1 AND ${MAX_E1RM_REPS}
  AND s.session_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
`;

/// The exercises worth offering in the picker, most-logged first -- the one
/// with the most data is the one whose chart will look like something.
async function readOptions(pool, userId, period = 'week') {
  const days = SUMMARY_WINDOWS[period];
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
  const days = SUMMARY_WINDOWS[period];
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

  const best = new Map();
  for (const row of rows) {
    const value = epley(toNumber(row.weight_kg), row.reps);
    const key = formatDate(row.session_date);
    if (!best.has(key) || value > best.get(key)) best.set(key, value);
  }

  return {
    xAxis: 'date',
    points: [...best.entries()].map(([label, value]) => ({
      label,
      e1rmKg: round1(value),
    })),
  };
}

/// One decimal. An estimate carrying six of them claims a precision it does
/// not have.
function round1(value) {
  return Math.round(value * 10) / 10;
}

module.exports = { epley, readOptions, readSeries, MAX_E1RM_REPS };
