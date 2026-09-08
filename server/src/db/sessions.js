'use strict';
const AppError = require('../lib/app-error');

/// `session_date` is a DATE, which mysql2 hands back as a JS Date in local
/// time. `toISOString()` would convert to UTC first and can therefore report
/// the previous day for anyone east of Greenwich, so format the local parts.
function formatDate(value) {
  if (typeof value === 'string') return value.slice(0, 10);
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/// DECIMAL arrives as a string -- mysql2 will not risk float precision on it.
/// Every weight and volume passes through here, because '22.50' + 8 is
/// '22.508' and a single missed conversion corrupts a volume total silently.
function toNumber(value) {
  return value === null || value === undefined ? null : Number(value);
}

function toLoggedSet(row) {
  return {
    exerciseId: row.exercise_id,
    setNumber: row.set_number,
    weightKg: toNumber(row.weight_kg),
    reps: row.reps,
  };
}

function toSession(row, setRows) {
  return {
    sessionId: row.session_id,
    planId: row.plan_id,
    status: row.status,
    sessionDate: formatDate(row.session_date),
    startedAt: row.started_at ? new Date(row.started_at).toISOString() : null,
    durationMin: row.duration_min,
    totalVolumeKg: toNumber(row.total_volume_kg),
    sets: setRows.map(toLoggedSet),
  };
}

async function loadSets(pool, sessionId) {
  const [rows] = await pool.query(
    `SELECT exercise_id, set_number, weight_kg, reps
     FROM set_logs
     WHERE session_id = ? AND is_completed = TRUE
     ORDER BY exercise_id, set_number`,
    [sessionId],
  );
  return rows;
}

/// Null when the id does not exist OR belongs to someone else -- the caller
/// cannot tell the two apart, which is what keeps ids unguessable.
async function getSessionById(pool, userId, sessionId) {
  if (!Number.isInteger(sessionId)) return null;
  const [rows] = await pool.query(
    'SELECT * FROM workout_sessions WHERE session_id = ? AND user_id = ?',
    [sessionId, userId],
  );
  if (rows.length === 0) return null;
  return toSession(rows[0], await loadSets(pool, rows[0].session_id));
}

async function getActiveSession(pool, userId) {
  const [rows] = await pool.query(
    `SELECT * FROM workout_sessions
     WHERE user_id = ? AND status = 'in_progress'
     ORDER BY session_id DESC
     LIMIT 1`,
    [userId],
  );
  if (rows.length === 0) return null;
  return toSession(rows[0], await loadSets(pool, rows[0].session_id));
}

/// Idempotent. Tapping Start, losing the response and tapping again must not
/// split one workout into two sessions -- every volume figure computed from
/// them would then be half right.
///
/// A plain "check, then insert" is not enough: two genuinely concurrent
/// calls (two devices, a double-tap) can both see "no active session" before
/// either has inserted, and both would insert. MySQL has no partial unique
/// index to enforce "at most one in_progress row per user" at the schema
/// level, and a plain UNIQUE (user_id, status) would also forbid a second
/// *completed* session, which is wrong. So the invariant is enforced here:
/// a per-user row lock (`SELECT ... FOR UPDATE` on the user's own row)
/// serializes concurrent starts for that user, and the active-session check
/// is redone inside that lock, on the same connection, before deciding to
/// insert.
async function startSession(pool, userId) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    // Serializes concurrent startSession calls for this user. Everything
    // below runs on `conn`, not `pool`, so it participates in this lock.
    await conn.query('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE', [userId]);

    const existing = await getActiveSession(conn, userId);
    if (existing) {
      await conn.commit();
      return { session: existing, created: false };
    }

    const [plans] = await conn.query(
      `SELECT plan_id FROM workout_plans
       WHERE user_id = ? AND is_active = TRUE
       ORDER BY plan_id DESC
       LIMIT 1`,
      [userId],
    );
    if (plans.length === 0) {
      throw AppError.conflict('NO_ACTIVE_PLAN', 'You have no active plan to train.');
    }

    const [res] = await conn.query(
      `INSERT INTO workout_sessions (user_id, plan_id, status, session_date, started_at)
       VALUES (?, ?, 'in_progress', CURDATE(), NOW())`,
      [userId, plans[0].plan_id],
    );

    const session = await getSessionById(conn, userId, res.insertId);
    await conn.commit();
    return { session, created: true };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = {
  formatDate,
  toNumber,
  getSessionById,
  getActiveSession,
  startSession,
};
