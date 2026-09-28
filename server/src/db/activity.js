'use strict';
const { estimateActivity } = require('../lib/activity-estimate');
const { dayNumber, dateOf } = require('../lib/streak');

const WEEK_DAYS = 7;
/// "Your usual" needs this many earlier days, so a single day is never it.
const USUAL_MIN_DAYS = 3;

async function bodyOf(db, userId) {
  const [[u]] = await db.query(
    'SELECT height_cm, weight_kg, sex FROM users WHERE user_id = ?', [userId],
  );
  return { heightCm: u ? u.height_cm : null, weightKg: u ? u.weight_kg : null, sex: u ? u.sex : null };
}

/// Saves [steps] for [date] and returns the day with its estimates. A stored
/// day is never lowered -- a late request or a second phone reporting less
/// leaves the higher count -- and the estimates are recomputed from the
/// kept count and the profile as it is now. Missing estimates are stored as
/// 0 (the columns are NOT NULL); `missing` says which.
async function saveDayOnce(pool, userId, date, steps) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[row]] = await conn.query(
      'SELECT steps FROM activity_logs WHERE user_id = ? AND log_date = ? FOR UPDATE',
      [userId, date],
    );
    const kept = row ? Math.max(row.steps, steps) : steps;
    const est = estimateActivity({ steps: kept, ...(await bodyOf(conn, userId)) });
    const day = {
      date,
      steps: kept,
      caloriesBurned: est.caloriesBurned ?? 0,
      distanceKm: est.distanceKm ?? 0,
      activeMinutes: est.activeMinutes,
    };
    await conn.query(
      `INSERT INTO activity_logs
         (user_id, log_date, steps, calories_burned, distance_km, active_minutes)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         steps = VALUES(steps),
         calories_burned = VALUES(calories_burned),
         distance_km = VALUES(distance_km),
         active_minutes = VALUES(active_minutes)`,
      [userId, date, day.steps, day.caloriesBurned, day.distanceKm, day.activeMinutes],
    );
    await conn.commit();
    return { ...day, missing: est.missing };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

/// Two first saves of the same day at once both pass the FOR UPDATE (gap
/// locks do not conflict) and InnoDB kills one as a deadlock. Running it
/// again sees the winner's row, so the higher count still wins.
async function saveDay(pool, userId, date, steps) {
  try {
    return await saveDayOnce(pool, userId, date, steps);
  } catch (err) {
    if (err.code !== 'ER_LOCK_DEADLOCK') throw err;
    return saveDayOnce(pool, userId, date, steps);
  }
}

/// The seven days ending [today] (YYYY-MM-DD), oldest first, with the
/// user's usual: the average steps of the earlier days that have a row,
/// null below USUAL_MIN_DAYS. Today is left out of it, so it never sets its
/// own comparison.
async function readWeek(pool, userId, today) {
  const first = dateOf(dayNumber(today) - (WEEK_DAYS - 1));
  const [rows] = await pool.query(
    `SELECT DATE_FORMAT(log_date, '%Y-%m-%d') AS date, steps, calories_burned,
            distance_km, active_minutes
       FROM activity_logs
      WHERE user_id = ? AND log_date BETWEEN ? AND ?
      ORDER BY log_date`,
    [userId, first, today],
  );
  const byDate = new Map(rows.map((r) => [r.date, {
    date: r.date,
    steps: r.steps,
    caloriesBurned: r.calories_burned,
    distanceKm: Number(r.distance_km),
    activeMinutes: r.active_minutes,
  }]));
  const days = [];
  for (let back = WEEK_DAYS - 1; back >= 0; back -= 1) {
    const date = dateOf(dayNumber(today) - back);
    days.push(byDate.get(date) || {
      date, steps: null, caloriesBurned: null, distanceKm: null, activeMinutes: null,
    });
  }
  const earlier = rows.filter((r) => r.date !== today);
  const usual = earlier.length >= USUAL_MIN_DAYS
    ? Math.round(earlier.reduce((sum, r) => sum + r.steps, 0) / earlier.length)
    : null;
  const { missing } = estimateActivity({ steps: 0, ...(await bodyOf(pool, userId)) });
  return { days, usual, usualDays: earlier.length, missing };
}

module.exports = { saveDay, readWeek };
