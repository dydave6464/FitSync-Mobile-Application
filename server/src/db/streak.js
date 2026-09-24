'use strict';
const { computeStreak } = require('../lib/streak');

/// Every date [userId] did something: ticked a habit -- a deleted one
/// included, since routine_checks is kept for exactly this -- or completed a
/// workout. Formatted in SQL, so no driver or host zone touches the date.
async function activeDates(pool, userId) {
  const [rows] = await pool.query(
    `SELECT DATE_FORMAT(c.check_date, '%Y-%m-%d') AS d
       FROM routine_checks c
       JOIN routine_habits h ON h.habit_id = c.habit_id
      WHERE h.user_id = ?
     UNION
     SELECT DATE_FORMAT(s.session_date, '%Y-%m-%d')
       FROM workout_sessions s
      WHERE s.user_id = ? AND s.status = 'completed'`,
    [userId, userId],
  );
  return rows.map((r) => r.d);
}

/// The streak as of the server's today: CURDATE(), which every pooled
/// connection runs in Manila time.
async function readStreak(pool, userId) {
  const [[{ today }]] = await pool.query(
    `SELECT DATE_FORMAT(CURDATE(), '%Y-%m-%d') AS today`,
  );
  return computeStreak(await activeDates(pool, userId), today);
}

module.exports = { activeDates, readStreak };
