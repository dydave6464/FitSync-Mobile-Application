'use strict';
const { GROUPS, groupOf } = require('../lib/muscle-groups');

/// When [userId] last trained each muscle group: untrained groups first (in
/// body order), then the longest rested, ties in body order.
///
/// A dated fact, not a recovery estimate: the app has no model of how
/// recovered a muscle is, so the card says when, never how ready. Any
/// completed set in a completed workout counts, bodyweight included -- it
/// trained the muscle even with nothing on the bar. daysAgo is counted
/// against CURDATE(), Manila's date.
async function readMuscleRecency(pool, userId) {
  const [rows] = await pool.query(
    `SELECT e.muscle_group AS muscle,
            DATE_FORMAT(MAX(s.session_date), '%Y-%m-%d') AS last_trained,
            DATEDIFF(CURDATE(), MAX(s.session_date)) AS days_ago
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
       JOIN exercises e ON e.exercise_id = sl.exercise_id
      WHERE s.user_id = ? AND s.status = 'completed' AND sl.is_completed = TRUE
      GROUP BY e.muscle_group`,
    [userId],
  );

  const latest = new Map();
  for (const r of rows) {
    const group = groupOf(r.muscle);
    if (!group) continue;
    const daysAgo = Number(r.days_ago);
    const seen = latest.get(group);
    if (!seen || daysAgo < seen.daysAgo) {
      latest.set(group, { lastTrained: r.last_trained, daysAgo });
    }
  }

  const bodyOrder = (group) => GROUPS.indexOf(group);
  return GROUPS
    .map((group) => ({
      group,
      lastTrained: latest.get(group)?.lastTrained ?? null,
      daysAgo: latest.get(group)?.daysAgo ?? null,
    }))
    .sort((a, b) => {
      if (a.daysAgo === null || b.daysAgo === null) {
        if (a.daysAgo !== b.daysAgo) return a.daysAgo === null ? -1 : 1;
        return bodyOrder(a.group) - bodyOrder(b.group);
      }
      return b.daysAgo - a.daysAgo || bodyOrder(a.group) - bodyOrder(b.group);
    });
}

module.exports = { readMuscleRecency };
