'use strict';
const { getProfile } = require('./profile');
const { readRankerHistory } = require('./ranker-history');

/// Real labelled rows for retraining the plan ranker
/// (ml/app/train_ranker.py --real). The columns are a contract with
/// train_ranker.CSV_COLUMNS: change both or neither.
///
/// One row per exercise a COMPLETED PLAN workout prescribed on its day, as the
/// day stood then (done 1 when a completed set was logged for it, else 0), and one per swap (the
/// exercise swapped out, done 0). Each row's history comes from
/// readRankerHistory(..., { before: event_date }): only what happened on
/// earlier days, so a row never sees its own outcome. Profile columns are the
/// profile as stored today -- its history is not kept.
const CSV_COLUMNS = [
  'user_id', 'event_date', 'kind', 'main_goal', 'fitness_level',
  'training_location', 'session_length_min', 'split_style', 'health_caution',
  'exercise_id', 'mark', 'beginner_friendly', 'equipment_name',
  'picked_equipment', 'muscle_group', 'days_since_trained', 'times_done',
  'times_skipped', 'times_swapped', 'done',
];

const ATTRIBUTES = `
  SELECT x.exercise_id, x.muscle_group,
         -- search_only / never are not plan marks: the CSV contract allows
         -- only first | alternative | unmarked (an old plan or a swap can
         -- still name such an exercise).
         CASE WHEN pref.priority IN ('first', 'alternative')
              THEN pref.priority ELSE 'unmarked' END AS mark,
         COALESCE(pref.beginner_friendly, 0) AS beginner_friendly,
         COALESCE(peq.name, eq.name) AS equipment_name,
         COALESCE(eq.parent_equipment_id, eq.equipment_id) AS root_equipment_id
    FROM exercises x
    JOIN equipment eq ON eq.equipment_id = x.equipment_id
    LEFT JOIN equipment peq ON peq.equipment_id = eq.parent_equipment_id
    LEFT JOIN exercise_preferences pref ON pref.exercise_id = x.exercise_id`;

async function exportRankerRows(pool) {
  // A swap rewrites its plan_exercises row in place, so the exercise a past
  // workout prescribed is reconstructed exactly as readRankerHistory does for
  // skips: the one rejected by the slot's first swap on a later day, else the
  // row's current one; a slot swapped ON the workout's day is left out (a DATE
  // cannot say whether the swap came before or after the workout).
  const [events] = await pool.query(
    `SELECT x.user_id, DATE_FORMAT(x.session_date, '%Y-%m-%d') AS event_date,
            'prescribed' AS kind, x.exercise_id, x.split_style, x.session_length_min,
            EXISTS (SELECT 1 FROM set_logs sl
                     WHERE sl.session_id = x.session_id
                       AND sl.exercise_id = x.exercise_id
                       AND sl.is_completed = TRUE) AS done
       FROM (
         SELECT s.user_id, s.session_id, s.session_date, p.split_style, p.session_length_min,
                COALESCE(
                  (SELECT w.rejected_exercise_id FROM plan_swaps w
                    WHERE w.plan_exercise_id = pe.plan_exercise_id
                      AND DATE(w.swapped_at) > s.session_date
                    ORDER BY w.swapped_at, w.swap_id
                    LIMIT 1),
                  pe.exercise_id) AS exercise_id
           FROM workout_sessions s
           JOIN workout_plans p ON p.plan_id = s.plan_id
           JOIN plan_exercises pe
             ON pe.plan_id = s.plan_id AND pe.day_no = COALESCE(s.plan_day_no, 1)
          WHERE s.status = 'completed'
            AND NOT EXISTS (
                  SELECT 1 FROM plan_swaps w
                   WHERE w.plan_exercise_id = pe.plan_exercise_id
                     AND DATE(w.swapped_at) = s.session_date)
       ) x
     UNION ALL
     SELECT w.user_id, DATE_FORMAT(w.swapped_at, '%Y-%m-%d'), 'swap',
            w.rejected_exercise_id, p.split_style, p.session_length_min, 0
       FROM plan_swaps w
       JOIN workout_plans p ON p.plan_id = w.plan_id
      ORDER BY 1, 2, 3, 4`,
  );
  const [attrRows] = await pool.query(ATTRIBUTES);
  const attrs = new Map(attrRows.map((a) => [a.exercise_id, a]));

  const profiles = new Map();
  const histories = new Map();
  const rows = [];
  for (const e of events) {
    if (!profiles.has(e.user_id)) profiles.set(e.user_id, await getProfile(pool, e.user_id));
    const profile = profiles.get(e.user_id);
    const key = `${e.user_id}|${e.event_date}`;
    if (!histories.has(key)) {
      histories.set(key, await readRankerHistory(pool, e.user_id, { before: e.event_date }));
    }
    const history = histories.get(key);
    const a = attrs.get(e.exercise_id);
    if (!profile || !a) continue;
    const picked = new Set((profile.equipment ?? []).map((q) => q.equipmentId));
    const counts = history.exercises[String(e.exercise_id)] ?? { done: 0, skipped: 0, swapped: 0 };
    const days = history.muscleDaysAgo[a.muscle_group];
    rows.push({
      user_id: e.user_id,
      event_date: e.event_date,
      kind: e.kind,
      main_goal: profile.mainGoal ?? '',
      fitness_level: profile.fitnessLevel ?? '',
      training_location: profile.trainingLocation ?? '',
      session_length_min: Number(e.session_length_min),
      split_style: e.split_style,
      health_caution: profile.healthCaution === true ? 1 : 0,
      exercise_id: e.exercise_id,
      mark: a.mark,
      beginner_friendly: a.beginner_friendly ? 1 : 0,
      equipment_name: a.equipment_name ?? '',
      picked_equipment: picked.has(a.root_equipment_id) ? 1 : 0,
      muscle_group: a.muscle_group,
      days_since_trained: days === undefined ? '' : days,
      times_done: counts.done,
      times_skipped: counts.skipped,
      times_swapped: counts.swapped,
      done: Number(e.done) ? 1 : 0,
    });
  }
  return rows;
}

function field(value) {
  const s = String(value ?? '');
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function toCsv(rows) {
  const lines = [CSV_COLUMNS.join(',')];
  for (const r of rows) lines.push(CSV_COLUMNS.map((c) => field(r[c])).join(','));
  return `${lines.join('\n')}\n`;
}

module.exports = { CSV_COLUMNS, exportRankerRows, toCsv };
