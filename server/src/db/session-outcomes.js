'use strict';
const AppError = require('../lib/app-error');
const { formatDate } = require('./sessions');

/// How far back a session may be and still be asked about. Delayed-onset pain
/// peaks 24-48 hours after training, and a week covers that plus an ordinary
/// gap between training days. Much beyond it, the rest of the user's life is
/// the likelier cause, and the answer would be noise attributed to a session.
/// Today itself is excluded (see pendingOutcome) so the window is seven whole
/// days before today, not eight counting today.
const OUTCOME_WINDOW_DAYS = 7;

/// session_outcomes.pain_level's ENUM, in the order the client shows it.
const PAIN_LEVELS = ['none', 'mild', 'moderate', 'severe'];

/// The session to ask "how did it leave you?" about, or null.
///
/// Only ever the user's MOST RECENT completed session, ordered exactly as
/// lastCompletedWorkout orders it. When that one is answered or stale, nothing
/// is pending -- even if an older session in the window was dismissed -- because
/// pain reported now is evidence about the last session, not an earlier one.
///
/// The window excludes today: a session that ended minutes ago has not had
/// time for delayed-onset pain to appear, and because of UNIQUE(session_id) an
/// early "none" would permanently block the later, meaningful answer. If the
/// latest session is today's, nothing is pending -- never fall back to an
/// older one, even an unanswered one still inside the window.
async function pendingOutcome(pool, userId) {
  const [rows] = await pool.query(
    `SELECT s.session_id, s.session_date, p.name AS plan_name, o.outcome_id,
            s.session_date >= CURDATE() - INTERVAL ? DAY
              AND s.session_date < CURDATE() AS in_window
       FROM workout_sessions s
       LEFT JOIN workout_plans p ON p.plan_id = s.plan_id
       LEFT JOIN session_outcomes o ON o.session_id = s.session_id
      WHERE s.user_id = ? AND s.status = 'completed'
      ORDER BY s.session_date DESC, s.session_id DESC
      LIMIT 1`,
    [OUTCOME_WINDOW_DAYS, userId],
  );
  if (rows.length === 0) return null;
  const row = rows[0];
  if (row.outcome_id !== null || !row.in_window) return null;
  return {
    sessionId: row.session_id,
    sessionDate: formatDate(row.session_date),
    planName: row.plan_name ?? null,
  };
}

/// Stores one answer. Null when the session is missing, someone else's, or not
/// completed -- the route turns all three into the same 404, so nothing about
/// another user's sessions leaks.
///
/// The UNIQUE key on session_id is the only duplicate check. A SELECT first
/// would still need this catch for two submits racing past it, so it would be
/// a second copy of the same rule.
async function recordOutcome(pool, userId, sessionId, { painLevel, injuryId }) {
  const [sessions] = await pool.query(
    `SELECT session_id FROM workout_sessions
      WHERE session_id = ? AND user_id = ? AND status = 'completed'`,
    [sessionId, userId],
  );
  if (sessions.length === 0) return null;

  if (injuryId !== null) {
    const [regions] = await pool.query(
      'SELECT injury_id FROM injuries WHERE injury_id = ?', [injuryId],
    );
    if (regions.length === 0) {
      throw AppError.badRequest('INJURY_INVALID', 'injuryId does not name a body region.');
    }
  }

  let inserted;
  try {
    [inserted] = await pool.query(
      `INSERT INTO session_outcomes (user_id, session_id, pain_level, injury_id)
       VALUES (?, ?, ?, ?)`,
      [userId, sessionId, painLevel, injuryId],
    );
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      throw AppError.conflict('OUTCOME_EXISTS', 'This session already has a report.');
    }
    throw err;
  }

  return { outcomeId: inserted.insertId, sessionId, painLevel, injuryId };
}

module.exports = { OUTCOME_WINDOW_DAYS, PAIN_LEVELS, pendingOutcome, recordOutcome };
