'use strict';

/// How many different exercises a free user gets AI cues for per day. Pro is
/// unlimited -- the manuscript's "unlimited AI-generated coaching cues".
const FREE_DAILY_AI_CUES = 3;

/// 'pro' (never counted), 'counted' (this exercise already used today),
/// 'available' (a new use fits today), or 'exhausted'.
async function allowanceFor(pool, userId, exerciseId) {
  const [[user]] = await pool.query(
    'SELECT is_premium FROM users WHERE user_id = ?', [userId],
  );
  if (user && user.is_premium) return 'pro';

  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS used, COALESCE(SUM(exercise_id = ?), 0) AS this_one
       FROM ai_cue_uses
      WHERE user_id = ? AND used_on = CURDATE()`,
    [exerciseId, userId],
  );
  if (Number(row.this_one) > 0) return 'counted';
  return Number(row.used) < FREE_DAILY_AI_CUES ? 'available' : 'exhausted';
}

/// Records that AI cues were shown. INSERT IGNORE: re-recording the same
/// exercise on the same day is a no-op, and two requests at the same instant
/// can at worst let one extra through.
async function recordUse(pool, userId, exerciseId) {
  await pool.query(
    'INSERT IGNORE INTO ai_cue_uses (user_id, used_on, exercise_id) VALUES (?, CURDATE(), ?)',
    [userId, exerciseId],
  );
}

module.exports = { FREE_DAILY_AI_CUES, allowanceFor, recordUse };
