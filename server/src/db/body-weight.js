'use strict';
const AppError = require('../lib/app-error');
const { formatDate, toNumber, periodDays } = require('./sessions');

// A plausible human range. `users.weight_kg` is unconstrained today, and this
// endpoint is about to become the main way it is written -- a typo landing
// 714 instead of 71.4 would break every chart that reads it afterwards, with
// no expiry to correct it.
const MIN_KG = 20;
const MAX_KG = 500;

// The same kind of bound for height. Like the weight bound it sits wider
// than the app's soft "ask once" range (100-250 cm), so a value the user
// confirmed still saves, while a slip such as 17 cm or 1.7 (metres) does not.
const MIN_CM = 50;
const MAX_CM = 275;

/// The hard range of each profile number, with the words the app shows when
/// a value falls outside it.
const BODY_RANGES = {
  heightCm: { min: MIN_CM, max: MAX_CM, unit: 'cm', noun: 'height' },
  weightKg: { min: MIN_KG, max: MAX_KG, unit: 'kg', noun: 'weight' },
  goalWeightKg: { min: MIN_KG, max: MAX_KG, unit: 'kg', noun: 'goal weight' },
};

/// A 400 for [field] outside its range. details[0] carries the range itself,
/// so the app can flag the field and restate the range in the user's unit.
function outOfRange(code, field) {
  const { min, max, unit, noun } = BODY_RANGES[field];
  return AppError.badRequest(
    code,
    `Enter a ${noun} between ${min} and ${max} ${unit}.`,
    [{ field, min, max, unit }],
  );
}

// How far a widened series may reach back. Enough to draw a shape, few enough
// that a user logging daily for a year does not ship 365 points to a card
// 84 pixels tall.
const MAX_POINTS = 24;

/// The weight series for one period, oldest point first.
///
/// `period` is a PREFERENCE, not a filter. A window holding fewer than two
/// entries cannot draw a line, and a card that goes blank because the user
/// picked "Week" three weeks after weighing in is worse than one showing
/// older truth. So a thin window widens to the most recent entries and says
/// so in `widened`, which the card turns into its caption.
///
/// Volume never does this -- its buckets are always full. Only the sparse,
/// user-driven series need it.
async function readSeries(pool, userId, period = 'week') {
  // periodDays, not a bare SUMMARY_WINDOWS lookup: indexing reads the
  // prototype chain, so 'constructor' comes back a truthy function, walks
  // past this guard and reaches the query as a bind parameter -- where
  // mysql2 stringifies it and MySQL reads it as a nought-day window,
  // answering 200 with a nonsense series instead of refusing.
  const days = periodDays(period);
  if (!days) return null;

  const [windowed] = await pool.query(
    `SELECT weight_kg, log_date
       FROM body_weight_logs
      WHERE user_id = ?
        AND log_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)
      ORDER BY log_date ASC`,
    [userId, days],
  );

  if (windowed.length >= 2) {
    return { widened: false, points: windowed.map(toPoint) };
  }

  const [recent] = await pool.query(
    `SELECT weight_kg, log_date
       FROM body_weight_logs
      WHERE user_id = ?
      ORDER BY log_date DESC
      LIMIT ?`,
    [userId, MAX_POINTS],
  );
  recent.reverse();

  return {
    widened: recent.length > windowed.length,
    points: recent.map(toPoint),
  };
}

function toPoint(row) {
  return { loggedOn: formatDate(row.log_date), weightKg: toNumber(row.weight_kg) };
}

/// The dashed line the chart draws behind the series.
///
/// This is what stops a first-day card being a lone dot. Both candidates are
/// the user's own numbers, so nothing is invented: the goal weight they
/// entered during onboarding, or -- failing that -- the weight they started
/// at, which stays worth seeing forever, since every later entry then reads
/// as above or below where they began.
async function readReference(pool, userId) {
  const [[user]] = await pool.query(
    'SELECT goal_weight_kg FROM users WHERE user_id = ?',
    [userId],
  );
  const goal = toNumber(user ? user.goal_weight_kg : null);
  if (goal !== null) return { kind: 'goal', weightKg: goal };

  const [[first]] = await pool.query(
    `SELECT weight_kg FROM body_weight_logs
      WHERE user_id = ? ORDER BY log_date ASC LIMIT 1`,
    [userId],
  );
  if (!first) return null;
  return { kind: 'start', weightKg: toNumber(first.weight_kg) };
}

/// The first weigh-in ever and how many there are, whatever the period.
///
/// The card's "since you started" needs the start weight even when a goal
/// weight, not the start, is the dashed reference line, and only offers it
/// once there are enough weigh-ins for it to mean something.
async function readStart(pool, userId) {
  const [[row]] = await pool.query(
    `SELECT (SELECT COUNT(*) FROM body_weight_logs WHERE user_id = ?) AS entries,
            weight_kg, log_date
       FROM body_weight_logs
      WHERE user_id = ? ORDER BY log_date ASC LIMIT 1`,
    [userId, userId],
  );
  if (!row) return { start: null, entries: 0 };
  return {
    start: { loggedOn: formatDate(row.log_date), weightKg: toNumber(row.weight_kg) },
    entries: Number(row.entries),
  };
}

/// Records a weigh-in and, when it is the newest one, syncs it to the profile.
///
/// One write updates both, so `users.weight_kg` and this table can never
/// disagree -- the bug you would only notice when the Profile screen and the
/// Progress chart show different numbers.
///
/// The sync is conditional on recency. Backfilling last month's weigh-in must
/// not overwrite what the profile shows today, so the profile UPDATE only fires
/// when the entry being written is the latest the user has. The row has already
/// been written at that point, so MAX(log_date) includes it and the comparison
/// is `>=`.
async function writeEntry(pool, userId, { weightKg, loggedOn = null }) {
  const weight = Number(weightKg);
  if (!Number.isFinite(weight) || weight < MIN_KG || weight > MAX_KG) {
    throw outOfRange('WEIGHT_OUT_OF_RANGE', 'weightKg');
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    // One user's weigh-ins and deletes run one at a time (see deleteEntry),
    // so users.weight_kg is always synced from a log no one else is changing.
    await conn.query('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE', [userId]);

    // Update-then-insert rather than ON DUPLICATE KEY UPDATE: the table has
    // no unique key on (user_id, log_date), and adding one would need an
    // ALTER that MIGRATIONS.md forbids. Weighing twice in a day is noise, so
    // the day's row is overwritten rather than appended to -- and the write
    // stays idempotent, which is what keeps a double tap on "Add entry" from
    // putting two points on one x.
    const [updated] = await conn.query(
      `UPDATE body_weight_logs SET weight_kg = ?
        WHERE user_id = ? AND log_date = COALESCE(?, CURDATE())`,
      [weight, userId, loggedOn],
    );

    if (updated.affectedRows === 0) {
      await conn.query(
        `INSERT INTO body_weight_logs (user_id, weight_kg, log_date)
         VALUES (?, ?, COALESCE(?, CURDATE()))`,
        [userId, weight, loggedOn],
      );
    }

    await conn.query(
      `UPDATE users
          SET weight_kg = ?
        WHERE user_id = ?
          AND COALESCE(?, CURDATE()) >= (
            SELECT MAX(log_date) FROM body_weight_logs WHERE user_id = ?
          )`,
      [weight, userId, loggedOn, userId],
    );

    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }

  const [[row]] = await pool.query(
    `SELECT weight_kg, log_date FROM body_weight_logs
      WHERE user_id = ? AND log_date = COALESCE(?, CURDATE())`,
    [userId, loggedOn],
  );
  return toPoint(row);
}

/// Removes the user's weigh-in on [loggedOn] (YYYY-MM-DD), every row of it:
/// with no unique key on the day, a race could have left two.
///
/// When that day was the newest, users.weight_kg moves to the newest weigh-in
/// left, so the profile and the chart agree; an older day leaves it alone.
/// The only weigh-in day is refused (409 ONLY_WEIGH_IN) rather than leaving an
/// empty chart beside a profile weight: logging the right weight for that day
/// replaces it instead.
///
/// Returns null when the user has no weigh-in that day, else what was deleted,
/// the start and count left (as readStart) and users.weight_kg afterwards.
async function deleteEntry(pool, userId, loggedOn) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    // Taken first, as writeEntry does, so a weigh-in landing at the same
    // moment waits rather than syncing users.weight_kg from a stale log.
    await conn.query('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE', [userId]);

    const [[day]] = await conn.query(
      `SELECT weight_kg, log_date,
              (SELECT COUNT(DISTINCT log_date) FROM body_weight_logs WHERE user_id = ?) AS days,
              log_date = (SELECT MAX(log_date) FROM body_weight_logs WHERE user_id = ?) AS newest
         FROM body_weight_logs
        WHERE user_id = ? AND log_date = ?
        ORDER BY weight_log_id DESC LIMIT 1`,
      [userId, userId, userId, loggedOn],
    );
    if (!day) {
      await conn.rollback();
      return null;
    }
    if (Number(day.days) <= 1) {
      throw AppError.conflict(
        'ONLY_WEIGH_IN',
        "You can't delete your only weigh-in. To fix it, log the right weight for that day. It replaces this one.",
      );
    }

    await conn.query(
      'DELETE FROM body_weight_logs WHERE user_id = ? AND log_date = ?', [userId, loggedOn],
    );
    if (Number(day.newest) === 1) {
      await conn.query(
        `UPDATE users
            SET weight_kg = (SELECT weight_kg FROM body_weight_logs
                              WHERE user_id = ?
                              ORDER BY log_date DESC, weight_log_id DESC LIMIT 1)
          WHERE user_id = ?`,
        [userId, userId],
      );
    }

    const left = await readStart(conn, userId);
    const [[user]] = await conn.query('SELECT weight_kg FROM users WHERE user_id = ?', [userId]);
    await conn.commit();
    return { deleted: toPoint(day), ...left, weightKg: toNumber(user.weight_kg) };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = {
  readSeries, readReference, readStart, writeEntry, deleteEntry, outOfRange,
  MIN_KG, MAX_KG, MIN_CM, MAX_CM, BODY_RANGES, MAX_POINTS,
};
