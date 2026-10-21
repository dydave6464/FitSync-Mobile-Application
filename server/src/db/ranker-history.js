'use strict';

/// What /generate-plan is told about a user's own training, for the plan
/// ranker (ml/app/ranker.py), and what the ranker export reads as-of each
/// event (scripts/export-ranker.js).
///
///   muscleDaysAgo  per CATALOGUE muscle group (exercises.muscle_group, not
///                  muscle-recency.js's six groups): days since the last
///                  completed workout with a completed set for it, capped
///   exercises      per exercise id: completed workouts in the window with a
///                  completed set (done); completed PLAN workouts that
///                  prescribed it on their day, as the day stood then, with
///                  none (skipped); swaps that rejected it (swapped). Capped;
///                  zeros left out.
///
/// [before] ('YYYY-MM-DD'): count only earlier days and measure against it.
/// null: up to and including today, measured against today (Manila: the
/// pool's session zone, see pool.js).
const WINDOW_DAYS = 90;
const COUNT_CAP = 5;
const DAYS_CAP = 14;

async function readRankerHistory(pool, userId, { before = null } = {}) {
  // ref is the day distances are measured from; the window is
  // [ref - 90 days, ref) when before is given, [today - 89, today] otherwise
  // -- both 90 days long.
  const ref = before === null ? 'CURDATE()' : '?';
  const upper = before === null ? 's.session_date <= CURDATE()' : 's.session_date < ?';
  const lowerFor = (col) => (before === null
    ? `${col} > CURDATE() - INTERVAL ${WINDOW_DAYS} DAY`
    : `${col} >= ? - INTERVAL ${WINDOW_DAYS} DAY`);

  const [muscles] = await pool.query(
    `SELECT e.muscle_group AS muscle, DATEDIFF(${ref}, MAX(s.session_date)) AS days
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
       JOIN exercises e ON e.exercise_id = sl.exercise_id
      WHERE s.user_id = ? AND s.status = 'completed' AND sl.is_completed = TRUE
        AND ${upper}
      GROUP BY e.muscle_group`,
    before === null ? [userId] : [before, userId, before],
  );

  const [done] = await pool.query(
    `SELECT sl.exercise_id AS id, COUNT(DISTINCT s.session_id) AS n
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
      WHERE s.user_id = ? AND s.status = 'completed' AND sl.is_completed = TRUE
        AND ${upper} AND ${lowerFor('s.session_date')}
      GROUP BY sl.exercise_id`,
    before === null ? [userId] : [userId, before, before],
  );

  // plan_exercises holds each slot as it is NOW: a swap rewrites the row in
  // place (plan-swap.js). So the slot's exercise AT a past session is the one
  // rejected by the first swap of that slot on a later day, or the row's
  // current one if it was not swapped since. A slot swapped ON the session's
  // day is left out: a DATE cannot say whether the swap came before or after
  // the workout. Not recoverable, and so still read from the current rows: a
  // custom-day replace (plans.js deletes and reinserts the day, nulling its
  // swaps' plan_exercise_id) and swaps recorded before plan_swaps existed.
  const [skipped] = await pool.query(
    `SELECT x.id, COUNT(DISTINCT x.session_id) AS n
       FROM (
         SELECT s.session_id,
                COALESCE(
                  (SELECT w.rejected_exercise_id FROM plan_swaps w
                    WHERE w.plan_exercise_id = pe.plan_exercise_id
                      AND DATE(w.swapped_at) > s.session_date
                    ORDER BY w.swapped_at, w.swap_id
                    LIMIT 1),
                  pe.exercise_id) AS id
           FROM workout_sessions s
           JOIN plan_exercises pe
             ON pe.plan_id = s.plan_id AND pe.day_no = COALESCE(s.plan_day_no, 1)
          WHERE s.user_id = ? AND s.status = 'completed' AND s.plan_id IS NOT NULL
            AND ${upper} AND ${lowerFor('s.session_date')}
            AND NOT EXISTS (
                  SELECT 1 FROM plan_swaps w
                   WHERE w.plan_exercise_id = pe.plan_exercise_id
                     AND DATE(w.swapped_at) = s.session_date)
       ) x
      WHERE NOT EXISTS (
              SELECT 1 FROM set_logs sl
               WHERE sl.session_id = x.session_id
                 AND sl.exercise_id = x.id
                 AND sl.is_completed = TRUE)
      GROUP BY x.id`,
    before === null ? [userId] : [userId, before, before],
  );

  const swapUpper = before === null ? 'DATE(w.swapped_at) <= CURDATE()' : 'DATE(w.swapped_at) < ?';
  const [swapped] = await pool.query(
    `SELECT w.rejected_exercise_id AS id, COUNT(*) AS n
       FROM plan_swaps w
      WHERE w.user_id = ? AND ${swapUpper} AND ${lowerFor('DATE(w.swapped_at)')}
      GROUP BY w.rejected_exercise_id`,
    before === null ? [userId] : [userId, before, before],
  );

  const muscleDaysAgo = {};
  for (const r of muscles) {
    muscleDaysAgo[r.muscle] = Math.min(Number(r.days), DAYS_CAP);
  }
  const exercises = {};
  const add = (rows, key) => {
    for (const r of rows) {
      const id = String(r.id);
      exercises[id] ??= { done: 0, skipped: 0, swapped: 0 };
      exercises[id][key] = Math.min(Number(r.n), COUNT_CAP);
    }
  };
  add(done, 'done');
  add(skipped, 'skipped');
  add(swapped, 'swapped');
  return { muscleDaysAgo, exercises };
}

module.exports = { readRankerHistory, WINDOW_DAYS, COUNT_CAP, DAYS_CAP };
