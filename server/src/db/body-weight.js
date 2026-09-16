'use strict';
const AppError = require('../lib/app-error');
const { formatDate, toNumber, SUMMARY_WINDOWS } = require('./sessions');

// A plausible human range. `users.weight_kg` is unconstrained today, and this
// endpoint is about to become the main way it is written -- a typo landing
// 714 instead of 71.4 would break every chart that reads it afterwards, with
// no expiry to correct it.
const MIN_KG = 20;
const MAX_KG = 500;

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
  const days = SUMMARY_WINDOWS[period];
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
    throw AppError.badRequest(
      'WEIGHT_OUT_OF_RANGE',
      `weightKg must be a number between ${MIN_KG} and ${MAX_KG}.`,
    );
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

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

module.exports = { readSeries, readReference, writeEntry, MIN_KG, MAX_KG, MAX_POINTS };
