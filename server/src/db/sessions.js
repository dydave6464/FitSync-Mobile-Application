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

/// TIMESTAMP columns come back rendered in the SESSION's time_zone -- 'SYSTEM'
/// on a default install -- and the pool's mysql2 `timezone: 'Z'` then LABELS
/// that local wall-clock string as UTC. It cannot undo a conversion the server
/// already did. On a UTC+8 host that reports a session as having started eight
/// hours in the future: the phone subtracts it from its own clock, gets a
/// negative, clamps to zero, and shows "0 min elapsed" for the whole workout
/// while storing durationMin: 0 on completion.
///
/// UNIX_TIMESTAMP() sidesteps the conversion rather than reversing it -- for a
/// TIMESTAMP argument MySQL hands back the internally stored UTC epoch
/// directly, consulting neither @@session.time_zone nor the zone-name tables.
/// getProfile uses the same remedy for created_at.
///
/// Every query whose rows reach toSession must select this.
const SESSION_COLUMNS = '*, UNIX_TIMESTAMP(started_at) AS started_at_epoch';

function toLoggedSet(row) {
  return {
    exerciseId: row.exercise_id,
    setNumber: row.set_number,
    weightKg: toNumber(row.weight_kg),
    reps: row.reps,
  };
}

function toSession(row, setRows, exerciseRows = []) {
  return {
    sessionId: row.session_id,
    planId: row.plan_id,
    // Empty for a plan-backed session, whose list still comes from the plan.
    // Present so a manual session -- which has neither a plan nor a rotation
    // day -- can say what it contains.
    exercises: exerciseRows,
    status: row.status,
    sessionDate: formatDate(row.session_date),
    startedAt: row.started_at_epoch
      ? new Date(Number(row.started_at_epoch) * 1000).toISOString()
      : null,
    durationMin: row.duration_min,
    planDayNo: row.plan_day_no,
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

/// A session's own chosen exercises, empty for a plan-backed session.
async function loadSessionExercises(pool, sessionId) {
  // Joined rather than id-only: the logger draws each exercise's name and its
  // artwork, so a list of bare ids leaves it rendering blank rows for a
  // session the user just picked by name.
  //
  // thumbnail_url comes back as the stored key. Turning a key into a URL is
  // the route's job here exactly as it is for plans -- the db layer does not
  // know the storage origin.
  const [rows] = await pool.query(
    `SELECT se.session_exercise_id, se.exercise_id, se.order_no,
            se.target_sets, se.target_reps,
            x.name, x.muscle_group, x.thumbnail_url
       FROM session_exercises se
       JOIN exercises x ON x.exercise_id = se.exercise_id
      WHERE se.session_id = ?
      ORDER BY se.order_no`,
    [sessionId],
  );
  return rows.map((row) => ({
    sessionExerciseId: row.session_exercise_id,
    exerciseId: row.exercise_id,
    orderNo: row.order_no,
    targetSets: row.target_sets,
    targetReps: row.target_reps,
    name: row.name,
    muscleGroup: row.muscle_group,
    thumbnailUrl: row.thumbnail_url,
  }));
}

/// Null when the id does not exist OR belongs to someone else -- the caller
/// cannot tell the two apart, which is what keeps ids unguessable.
async function getSessionById(pool, userId, sessionId) {
  if (!Number.isInteger(sessionId)) return null;
  const [rows] = await pool.query(
    `SELECT ${SESSION_COLUMNS} FROM workout_sessions
     WHERE session_id = ? AND user_id = ?`,
    [sessionId, userId],
  );
  if (rows.length === 0) return null;
  return toSession(
    rows[0],
    await loadSets(pool, rows[0].session_id),
    await loadSessionExercises(pool, rows[0].session_id),
  );
}

async function getActiveSession(pool, userId) {
  const [rows] = await pool.query(
    `SELECT ${SESSION_COLUMNS} FROM workout_sessions
     WHERE user_id = ? AND status = 'in_progress'
     ORDER BY session_id DESC
     LIMIT 1`,
    [userId],
  );
  if (rows.length === 0) return null;
  return toSession(
    rows[0],
    await loadSets(pool, rows[0].session_id),
    await loadSessionExercises(pool, rows[0].session_id),
  );
}

/// Which rotation day today's session is.
///
/// (sessions completed this week mod rotation) + 1. Counting completions
/// rather than mapping days onto weekdays is what stops a missed Monday
/// stranding someone: the rotation advances when you actually train, so a
/// skipped day costs a day rather than a session. It also wraps inside a week
/// with no special case -- the fourth session of a four-day push/pull/legs
/// week is 3 mod 3 + 1, Push again.
///
/// Abandoned and in-progress sessions do not count, which is what makes the
/// first session of a week day 1 and lets someone abandon one and start again
/// onto the same day.
///
/// Chosen training days (user_training_days) are deliberately NOT consulted
/// here. They drive the week strip's missed marker and nothing else. Pinning
/// the workout to the weekday would leave the rotation with no answer for
/// someone who trains on a day they did not choose, and would turn a missed
/// session into a lost one rather than a late one. See
/// docs/superpowers/specs/2026-09-14-training-days-design.md, section 0.
///
/// Exported for tests/sessions-db.test.js, which pins the decision above by
/// asserting that changing chosen days never changes this function's output.
async function nextPlanDayNo(conn, userId, rotation) {
  if (!rotation || rotation < 1) return 1;
  const [rows] = await conn.query(
    `SELECT COUNT(*) AS done
       FROM workout_sessions
      WHERE user_id = ?
        AND status = 'completed'
        AND session_date >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)`,
    [userId],
  );
  return (Number(rows[0].done) % rotation) + 1;
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
async function startSession(pool, userId, exerciseIds = null) {
  const manual = Array.isArray(exerciseIds) && exerciseIds.length > 0;
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

    // A chosen list is its own session: no plan, and so no rotation day to
    // stamp. NO_ACTIVE_PLAN stays on the other path, which is the one that
    // actually needs a plan.
    let planId = null;
    let planDayNo = null;

    if (!manual) {
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
      planId = plans[0].plan_id;

      // The rotation is a property of the split, not of days_per_week. Reading
      // it from the rows rather than from the split name keeps the stamped day
      // within what the plan actually contains, in case its generator produced
      // fewer days than the split name implies.
      const [dayRows] = await conn.query(
        'SELECT MAX(day_no) AS rotation FROM plan_exercises WHERE plan_id = ?',
        [planId],
      );
      planDayNo = await nextPlanDayNo(conn, userId, Number(dayRows[0].rotation) || 1);
    }

    const [res] = await conn.query(
      `INSERT INTO workout_sessions (user_id, plan_id, plan_day_no, status, session_date, started_at)
       VALUES (?, ?, ?, 'in_progress', CURDATE(), NOW())`,
      [userId, planId, planDayNo],
    );

    if (manual) {
      // Checked inside the transaction so a bad id rolls the session back with
      // it. Validating first and inserting after would leave a window for a
      // curator to retire an exercise between the two.
      const [live] = await conn.query(
        "SELECT exercise_id FROM exercises WHERE exercise_id IN (?) AND status = 'live'",
        [exerciseIds],
      );
      if (live.length !== exerciseIds.length) {
        throw AppError.badRequest(
          'INVALID_EXERCISE_IDS',
          'Every exercise must be one from the library.',
        );
      }

      await conn.query(
        'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES ?',
        [exerciseIds.map((id, index) => [res.insertId, id, index + 1])],
      );
    }

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

/// Shared by both writers: a session you do not own is indistinguishable from
/// one that does not exist, and a closed session accepts no edits.
async function requireInProgress(pool, userId, sessionId) {
  const session = await getSessionById(pool, userId, sessionId);
  if (!session) return null;
  if (session.status !== 'in_progress') {
    throw AppError.conflict(
      'SESSION_NOT_IN_PROGRESS',
      'This session has already been closed.',
    );
  }
  return session;
}

async function logSet(pool, userId, sessionId, { exerciseId, setNumber, weightKg, reps }) {
  const session = await requireInProgress(pool, userId, sessionId);
  if (!session) return null;

  // Which list this session is FOR decides which list to ask. A manual
  // session carries its own; a plan-backed one derives it. Asking
  // plan_exercises unconditionally refused every set in a manual session,
  // whose planId is null so the lookup matched nothing.
  const [chosen] = await pool.query(
    'SELECT 1 FROM session_exercises WHERE session_id = ? AND exercise_id = ? LIMIT 1',
    [sessionId, exerciseId],
  );
  if (chosen.length === 0) {
    const [anyChosen] = await pool.query(
      'SELECT 1 FROM session_exercises WHERE session_id = ? LIMIT 1',
      [sessionId],
    );
    if (anyChosen.length > 0) {
      // This session has a list of its own and the exercise is not on it.
      // Naming a plan here would describe something it does not have.
      throw AppError.badRequest(
        'EXERCISE_NOT_IN_SESSION',
        'That exercise is not part of this session.',
      );
    }

    const [inPlan] = await pool.query(
      `SELECT 1 FROM plan_exercises
       WHERE plan_id = ? AND exercise_id = ?
       LIMIT 1`,
      [session.planId, exerciseId],
    );
    if (inPlan.length === 0) {
      throw AppError.badRequest(
        'EXERCISE_NOT_IN_PLAN',
        'That exercise is not part of this session.',
      );
    }
  }

  // The unique key (session_id, exercise_id, set_number) from migration 002 is
  // what makes this idempotent: a retried request updates one row instead of
  // adding a second. VALUES() is deprecated in MySQL 8.0.20+ in favour of a row
  // alias, but still supported and kept here for the wider version floor.
  await pool.query(
    `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
     VALUES (?, ?, ?, ?, ?, TRUE)
     ON DUPLICATE KEY UPDATE
       weight_kg = VALUES(weight_kg),
       reps = VALUES(reps),
       is_completed = TRUE`,
    [sessionId, exerciseId, setNumber, weightKg, reps],
  );

  return { exerciseId, setNumber, weightKg: toNumber(weightKg), reps };
}

/// Deletes rather than flagging: a mis-tapped set did not happen, and a zeroed
/// row would have to be filtered out of every aggregate downstream forever.
async function deleteSet(pool, userId, sessionId, exerciseId, setNumber) {
  const session = await requireInProgress(pool, userId, sessionId);
  if (!session) return false;

  await pool.query(
    'DELETE FROM set_logs WHERE session_id = ? AND exercise_id = ? AND set_number = ?',
    [sessionId, exerciseId, setNumber],
  );
  return true;
}

/// Volume is computed here, never accepted from the client. Progress, personal
/// records and eventually the plan ranker all read this number, so it has to
/// mean one thing computed one way.
///
/// SUM skips NULLs, so a bodyweight set contributes nothing and COALESCE turns
/// an all-bodyweight session into 0 rather than NULL -- "I trained and lifted
/// no external load" is a different statement from "unknown".
///
/// ONE statement, deliberately. Summing in a separate SELECT left two windows
/// open, because [requireInProgress] and the write are separate round trips
/// and nothing here holds a transaction:
///
///  * a set INSERT committing between the sum and the UPDATE was left out of
///    total_volume_kg permanently -- short by that set for good, while
///    set_logs and lastPerformance still returned it. Tick the last set, tap
///    Finish ~300ms later, and the client does not disable Finish meanwhile.
///  * two concurrent completes could both pass the guard and both write,
///    where the second must lose with a 409.
///
/// Summing inside the UPDATE closes the first; `status = 'in_progress'` in
/// its WHERE closes the second. `set_logs` is a different table from the one
/// being updated, so MySQL allows the subquery. [requireInProgress] stays for
/// the ownership check: it must still return null for someone else's session
/// so the route answers 404 rather than admitting the id exists.
async function completeSession(pool, userId, sessionId, durationMin) {
  const session = await requireInProgress(pool, userId, sessionId);
  if (!session) return null;

  const [res] = await pool.query(
    `UPDATE workout_sessions
        SET status = 'completed',
            duration_min = ?,
            total_volume_kg = (SELECT COALESCE(SUM(weight_kg * reps), 0)
                                 FROM set_logs
                                WHERE session_id = ? AND is_completed = TRUE)
      WHERE session_id = ? AND status = 'in_progress'`,
    [durationMin, sessionId, sessionId],
  );

  // Matched nothing: the guard passed, then someone else closed the session
  // before this landed. Same answer the guard itself would have given a
  // moment later -- never a silent overwrite of the winner's numbers.
  // (status always changes here, so a matched row is always an affected one.)
  if (res.affectedRows === 0) {
    throw AppError.conflict(
      'SESSION_NOT_IN_PROGRESS',
      'This session has already been closed.',
    );
  }

  return getSessionById(pool, userId, sessionId);
}

/// No volume is stamped: an abandoned session is not a training record, and
/// giving it one would put it into every total that filters on status alone.
async function abandonSession(pool, userId, sessionId) {
  const session = await requireInProgress(pool, userId, sessionId);
  if (!session) return false;

  await pool.query(
    "UPDATE workout_sessions SET status = 'abandoned' WHERE session_id = ?",
    [sessionId],
  );
  return true;
}

const MAX_LAST_PERFORMANCE_IDS = 50;

/// The heaviest set of the most recent COMPLETED session, per exercise.
///
/// Heaviest rather than last: the final set of an exercise is usually the one
/// where form broke down, and prefilling that number tells the user to start
/// their next session lighter than they finished.
///
/// The subquery picks the latest session per exercise; the outer query returns
/// every set from those sessions and the reduce below keeps the heaviest. Done
/// in JS rather than SQL to stay clear of window functions.
async function lastPerformance(pool, userId, exerciseIds) {
  const ids = [...new Set(exerciseIds)]
    .filter(Number.isInteger)
    .slice(0, MAX_LAST_PERFORMANCE_IDS);
  if (ids.length === 0) return [];

  const [rows] = await pool.query(
    `SELECT sl.exercise_id, sl.weight_kg, sl.reps, ws.session_date
     FROM set_logs sl
     JOIN workout_sessions ws ON ws.session_id = sl.session_id
     JOIN (
       SELECT sl2.exercise_id, MAX(ws2.session_id) AS session_id
       FROM set_logs sl2
       JOIN workout_sessions ws2 ON ws2.session_id = sl2.session_id
       WHERE ws2.user_id = ?
         AND ws2.status = 'completed'
         AND sl2.is_completed = TRUE
         AND sl2.exercise_id IN (?)
       GROUP BY sl2.exercise_id
     ) latest
       ON latest.exercise_id = sl.exercise_id
      AND latest.session_id = sl.session_id
     WHERE sl.is_completed = TRUE
     ORDER BY sl.exercise_id, sl.set_number`,
    [userId, ids],
  );

  // When sets tie on weight -- always true for a bodyweight exercise, where
  // every set has a NULL weight -- the ORDER BY above makes set_number 1 the
  // deterministic winner instead of whatever order MySQL happened to return.
  const best = new Map();
  for (const row of rows) {
    const weight = toNumber(row.weight_kg) ?? 0;
    const current = best.get(row.exercise_id);
    if (!current || weight > current.weightKg) {
      best.set(row.exercise_id, {
        exerciseId: row.exercise_id,
        weightKg: toNumber(row.weight_kg),
        reps: row.reps,
        sessionDate: formatDate(row.session_date),
      });
    }
  }
  return [...best.values()];
}

/// WEEKDAY() is 0 on Monday, so subtracting it lands on this week's Monday --
/// which is where the Plan tab's strip starts.

/// How far back each summary window reaches, in days.
///
/// Rolling, not calendar. A calendar week starting Monday means that on a
/// Monday "this week" holds only today, so the same code reports a wildly
/// different number depending on which day it runs -- and a test asserting
/// two sessions passes on a Wednesday and fails on a Monday. The week strip
/// on Home is calendar-based because it draws named weekdays; a total is not
/// a calendar, so it is not bound to one.
const SUMMARY_WINDOWS = { week: 7, month: 30, year: 365 };

/// How many days [period] covers, or null when it names no window at all.
///
/// Object.hasOwn rather than a bare SUMMARY_WINDOWS[period]: the object
/// inherits from Object.prototype, so period='constructor' reads a function
/// off the prototype chain and passes a truthiness check. The null return is
/// what the routes turn into a 400, so a bare lookup turns a bad query
/// parameter into a 500 instead.
function periodDays(period) {
  return Object.hasOwn(SUMMARY_WINDOWS, period) ? SUMMARY_WINDOWS[period] : null;
}

/// How many sets a session holds. A correlated subquery rather than a GROUP
/// BY: a session with no sets at all must still appear with a count of 0,
/// which an inner join to set_logs would drop.
const SET_COUNT = `(SELECT COUNT(*) FROM set_logs l WHERE l.session_id = s.session_id)`;

/// How many exercises a session held.
///
/// Two sources, because sessions have two shapes: a hand-picked session owns
/// its list in session_exercises, and a plan-backed one borrows the plan's
/// rows for the rotation day it was stamped with. Coalescing on "did this
/// session own any rows" keeps both honest without a UNION.
const EXERCISE_COUNT = `(
  CASE WHEN EXISTS (SELECT 1 FROM session_exercises se WHERE se.session_id = s.session_id)
       THEN (SELECT COUNT(*) FROM session_exercises se WHERE se.session_id = s.session_id)
       ELSE (SELECT COUNT(*) FROM plan_exercises pe
              WHERE pe.plan_id = s.plan_id AND pe.day_no = COALESCE(s.plan_day_no, 1))
  END)`;

function toHistoryRow(row) {
  return {
    sessionId: row.session_id,
    sessionDate: formatDate(row.session_date),
    startedAt: row.started_at_epoch
      ? new Date(Number(row.started_at_epoch) * 1000).toISOString()
      : null,
    durationMin: row.duration_min,
    totalVolumeKg: toNumber(row.total_volume_kg),
    setCount: Number(row.set_count),
    exerciseCount: Number(row.exercise_count),
    // Read from the plan the session actually ran under, not from whichever
    // plan is active now: regenerating must not rewrite what you already did.
    // Null is what lets the client name a hand-picked session as its own.
    planName: row.plan_name ?? null,
  };
}

/// Completed sessions, newest first.
///
/// Completed only: `in_progress` is the workout you are in and `abandoned` is
/// one you threw away. Neither is something you did, and listing them would
/// make the screen read as a log of attempts rather than of training.
async function listHistory(pool, userId, { page = 1, limit = 20 } = {}) {
  const offset = (page - 1) * limit;

  const [[{ total }]] = await pool.query(
    `SELECT COUNT(*) AS total FROM workout_sessions
      WHERE user_id = ? AND status = 'completed'`,
    [userId],
  );

  const [rows] = await pool.query(
    `SELECT s.session_id, s.session_date, s.duration_min, s.total_volume_kg,
            UNIX_TIMESTAMP(s.started_at) AS started_at_epoch,
            p.name AS plan_name,
            ${SET_COUNT} AS set_count,
            ${EXERCISE_COUNT} AS exercise_count
       FROM workout_sessions s
       LEFT JOIN workout_plans p ON p.plan_id = s.plan_id
      WHERE s.user_id = ? AND s.status = 'completed'
      ORDER BY s.session_date DESC, s.session_id DESC
      LIMIT ? OFFSET ?`,
    [userId, limit, offset],
  );

  return { sessions: rows.map(toHistoryRow), total, page, limit };
}

/// Completed sessions INSIDE [period]'s window, newest first.
///
/// A period-aware twin of listHistory rather than an option bolted onto it:
/// listHistory is the app's all-time "Recent" list and has to stay unwindowed,
/// because the History screen pages through everything a user has ever done.
/// A shared report is the opposite case -- it captions itself with a window
/// ("week - 2026-09-12 to 2026-09-19"), so a list reaching months past that
/// caption makes the page contradict itself to a reader who has no other
/// context to catch it with.
///
/// `>=` against CURDATE(), matching summariseHistory rather than the analytics
/// readers' `>`: the summary line at the top of the same report counts its
/// sessions that way, and a stricter comparison here would print fewer rows
/// than the count sitting directly above them.
///
/// Null for a period that names no window -- the signal every other reader
/// here uses, and what the routes turn into a 400.
async function listHistoryInWindow(pool, userId, period, { limit = 20 } = {}) {
  const days = periodDays(period);
  if (!days) return null;

  const [rows] = await pool.query(
    `SELECT s.session_id, s.session_date, s.duration_min, s.total_volume_kg,
            UNIX_TIMESTAMP(s.started_at) AS started_at_epoch,
            p.name AS plan_name,
            ${SET_COUNT} AS set_count,
            ${EXERCISE_COUNT} AS exercise_count
       FROM workout_sessions s
       LEFT JOIN workout_plans p ON p.plan_id = s.plan_id
      WHERE s.user_id = ? AND s.status = 'completed'
        AND s.session_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
      ORDER BY s.session_date DESC, s.session_id DESC
      LIMIT ?`,
    [userId, days, limit],
  );

  return rows.map(toHistoryRow);
}

/// What the last [period] added up to. Zeroes, never null, for an account
/// that has trained nothing yet -- that is the state a new user is in, and it
/// has to read as "nothing yet" rather than as a broken screen.
async function summariseHistory(pool, userId, period = 'week') {
  const days = periodDays(period);
  if (!days) return null;

  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS session_count,
            COALESCE(SUM(s.total_volume_kg), 0) AS total_volume_kg,
            COALESCE(SUM(${SET_COUNT}), 0) AS set_count
       FROM workout_sessions s
      WHERE s.user_id = ? AND s.status = 'completed'
        AND s.session_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)`,
    [userId, days],
  );

  return {
    sessionCount: Number(row.session_count),
    setCount: Number(row.set_count),
    totalVolumeKg: toNumber(row.total_volume_kg) ?? 0,
  };
}


/// The exercises of the most recently completed workout, for repeating it.
///
/// Two sources, the same split logSet already makes: a hand-picked session
/// owns its list in session_exercises, and a plan-backed one borrows the
/// plan's rows for the rotation day it trained. The day matters -- borrowing
/// the whole plan would offer to repeat three days of training as one workout.
///
/// Live exercises only. Exercises are never deleted -- set_logs holds a
/// RESTRICT key to them -- so one leaves the catalogue by being demoted back
/// to 'pending'. A workout can be months old, so refusing the whole repeat
/// because one movement was demoted would leave the user no way to do the
/// rest of it. Everything the picker draws comes back with it, because a list
/// of bare ids renders blank rows for a workout the user recognises by name.
async function lastCompletedWorkout(pool, userId) {
  const [rows] = await pool.query(
    `SELECT s.session_id, s.session_date, s.plan_id, s.plan_day_no, p.name AS plan_name
       FROM workout_sessions s
       LEFT JOIN workout_plans p ON p.plan_id = s.plan_id
      WHERE s.user_id = ? AND s.status = 'completed'
      ORDER BY s.session_date DESC, s.session_id DESC
      LIMIT 1`,
    [userId],
  );
  if (rows.length === 0) return null;
  const row = rows[0];

  const [own] = await pool.query(
    `SELECT x.exercise_id, x.name, x.muscle_group, x.thumbnail_url, e.name AS equipment
       FROM session_exercises se
       JOIN exercises x ON x.exercise_id = se.exercise_id
       LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
      WHERE se.session_id = ? AND x.status = 'live'
      ORDER BY se.order_no`,
    [row.session_id],
  );

  let exercises = own;
  if (exercises.length === 0 && row.plan_id !== null) {
    const [fromPlan] = await pool.query(
      `SELECT x.exercise_id, x.name, x.muscle_group, x.thumbnail_url, e.name AS equipment
         FROM plan_exercises pe
         JOIN exercises x ON x.exercise_id = pe.exercise_id
         LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
        WHERE pe.plan_id = ? AND pe.day_no = ? AND x.status = 'live'
        ORDER BY pe.order_no`,
      [row.plan_id, row.plan_day_no ?? 1],
    );
    exercises = fromPlan;
  }

  // Null rather than an empty list: a workout of no exercises is not a
  // workout, and the sheet must not offer to repeat nothing.
  if (exercises.length === 0) return null;

  return {
    sessionId: row.session_id,
    sessionDate: formatDate(row.session_date),
    planName: row.plan_name ?? null,
    exercises: exercises.map((e) => ({
      exerciseId: e.exercise_id,
      name: e.name,
      muscleGroup: e.muscle_group,
      equipment: e.equipment ?? null,
      // The stored key. Turning it into a URL is the route's job, exactly as
      // it is for the rest of the session payloads.
      thumbnailUrl: e.thumbnail_url,
    })),
  };
}

async function completedThisWeek(pool, userId) {
  const [rows] = await pool.query(
    `SELECT DISTINCT session_date
     FROM workout_sessions
     WHERE user_id = ?
       AND status = 'completed'
       AND session_date >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
     ORDER BY session_date`,
    [userId],
  );
  return rows.map((row) => formatDate(row.session_date));
}

module.exports = {
  formatDate,
  toNumber,
  getSessionById,
  getActiveSession,
  startSession,
  logSet,
  deleteSet,
  completeSession,
  abandonSession,
  lastPerformance,
  completedThisWeek,
  listHistory,
  listHistoryInWindow,
  summariseHistory,
  lastCompletedWorkout,
  SUMMARY_WINDOWS,
  periodDays,
  nextPlanDayNo,
};
