'use strict';
const AppError = require('../lib/app-error');

/// The day to report, and its weekday (1 = Monday).
///
/// [date] exists for tests, so weekday logic never depends on when the suite
/// runs. The routes never pass it: "today" is the server's CURDATE(), the same
/// clock workout_sessions.session_date is written with, so the workout item and
/// the habits always agree on what day it is.
async function resolveDay(pool, date) {
  const [[row]] = await pool.query(
    `SELECT DATE_FORMAT(COALESCE(?, CURDATE()), '%Y-%m-%d') AS day,
            WEEKDAY(COALESCE(?, CURDATE())) + 1 AS weekday`,
    [date, date],
  );
  return { day: row.day, weekday: Number(row.weekday) };
}

/// TIME arrives as 'HH:MM:SS'; the API speaks 'HH:MM'.
function hhmm(time) {
  return time === null || time === undefined ? null : String(time).slice(0, 5);
}

async function weekdaysFor(pool, habitIds) {
  const map = new Map(habitIds.map((id) => [id, []]));
  if (habitIds.length === 0) return map;
  const [rows] = await pool.query(
    `SELECT habit_id, weekday FROM routine_habit_days
      WHERE habit_id IN (?) ORDER BY weekday`,
    [habitIds],
  );
  for (const r of rows) map.get(r.habit_id).push(Number(r.weekday));
  return map;
}

function toHabit(row, weekdays) {
  return {
    habitId: row.habit_id,
    title: row.title,
    time: hhmm(row.scheduled_time),
    durationMin: row.duration_min ?? null,
    weekdays,
    done: Boolean(row.done),
  };
}

/// Today's automatic workout item, or null.
///
/// Present when there is an active plan and today is a training day -- every
/// day is one when none are chosen, which is exactly how the week strip reads
/// user_training_days. A session completed today makes it present and done
/// whatever the day, because the workout happened. Never ticked by hand.
async function workoutItem(pool, userId, day, weekday) {
  const [[plan]] = await pool.query(
    'SELECT name FROM workout_plans WHERE user_id = ? AND is_active = TRUE LIMIT 1',
    [userId],
  );
  const [[session]] = await pool.query(
    `SELECT 1 AS done FROM workout_sessions
      WHERE user_id = ? AND status = 'completed' AND session_date = ? LIMIT 1`,
    [userId, day],
  );
  const title = plan ? plan.name : 'Workout';
  if (session) return { title, done: true };
  if (!plan) return null;

  const [chosen] = await pool.query(
    'SELECT weekday FROM user_training_days WHERE user_id = ?', [userId],
  );
  const days = chosen.map((r) => Number(r.weekday));
  if (days.length > 0 && !days.includes(weekday)) return null;
  return { title, done: false };
}

/// Active habits that repeat on [date]'s weekday -- timed ones by time, then
/// untimed ones by title -- each with that day's tick, plus the workout item.
async function readDay(pool, userId, date = null) {
  const { day, weekday } = await resolveDay(pool, date);
  const [rows] = await pool.query(
    `SELECT h.habit_id, h.title, h.scheduled_time, h.duration_min,
            EXISTS (SELECT 1 FROM routine_checks c
                     WHERE c.habit_id = h.habit_id AND c.check_date = ?) AS done
       FROM routine_habits h
      WHERE h.user_id = ? AND h.is_active = TRUE
        AND EXISTS (SELECT 1 FROM routine_habit_days d
                     WHERE d.habit_id = h.habit_id AND d.weekday = ?)
      ORDER BY h.scheduled_time IS NULL, h.scheduled_time, h.title, h.habit_id`,
    [day, userId, weekday],
  );
  const days = await weekdaysFor(pool, rows.map((r) => r.habit_id));
  return {
    date: day,
    habits: rows.map((r) => toHabit(r, days.get(r.habit_id))),
    workout: await workoutItem(pool, userId, day, weekday),
  };
}

/// One habit with [date]'s tick, or null when it is missing, someone else's,
/// or deleted -- the three cases the routes answer with the same 404.
async function readHabit(pool, userId, habitId, date = null) {
  const { day } = await resolveDay(pool, date);
  const [rows] = await pool.query(
    `SELECT h.habit_id, h.title, h.scheduled_time, h.duration_min,
            EXISTS (SELECT 1 FROM routine_checks c
                     WHERE c.habit_id = h.habit_id AND c.check_date = ?) AS done
       FROM routine_habits h
      WHERE h.habit_id = ? AND h.user_id = ? AND h.is_active = TRUE`,
    [day, habitId, userId],
  );
  if (rows.length === 0) return null;
  const days = await weekdaysFor(pool, [habitId]);
  return toHabit(rows[0], days.get(habitId));
}

async function writeWeekdays(conn, habitId, weekdays) {
  await conn.query('DELETE FROM routine_habit_days WHERE habit_id = ?', [habitId]);
  await conn.query(
    'INSERT INTO routine_habit_days (habit_id, weekday) VALUES ?',
    [weekdays.map((d) => [habitId, d])],
  );
}

/// One transaction, so a habit never exists without its weekdays.
async function createHabit(pool, userId, { title, time = null, durationMin = null, weekdays }) {
  const conn = await pool.getConnection();
  let habitId;
  try {
    await conn.beginTransaction();
    const [res] = await conn.query(
      `INSERT INTO routine_habits (user_id, title, scheduled_time, duration_min)
       VALUES (?, ?, ?, ?)`,
      [userId, title, time, durationMin],
    );
    habitId = res.insertId;
    await writeWeekdays(conn, habitId, weekdays);
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
  return readHabit(pool, userId, habitId);
}

/// Only the keys present in [fields] change; `time: null` and
/// `durationMin: null` clear. Null when the habit cannot be edited.
async function updateHabit(pool, userId, habitId, fields) {
  if (!(await readHabit(pool, userId, habitId))) return null;

  const columns = [];
  const values = [];
  if (fields.title !== undefined) { columns.push('title = ?'); values.push(fields.title); }
  if (fields.time !== undefined) { columns.push('scheduled_time = ?'); values.push(fields.time); }
  if (fields.durationMin !== undefined) { columns.push('duration_min = ?'); values.push(fields.durationMin); }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    if (columns.length > 0) {
      await conn.query(
        `UPDATE routine_habits SET ${columns.join(', ')} WHERE habit_id = ? AND user_id = ?`,
        [...values, habitId, userId],
      );
    }
    if (fields.weekdays !== undefined) await writeWeekdays(conn, habitId, fields.weekdays);
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
  return readHabit(pool, userId, habitId);
}

/// Soft: the habit leaves every future list, and its routine_checks history
/// stays for the streak that will one day read it.
async function deactivateHabit(pool, userId, habitId) {
  const [res] = await pool.query(
    `UPDATE routine_habits SET is_active = FALSE
      WHERE habit_id = ? AND user_id = ? AND is_active = TRUE`,
    [habitId, userId],
  );
  return res.affectedRows > 0;
}

/// Ticks or unticks [date]. Both directions are idempotent: the UNIQUE key
/// absorbs a second tick, and a second untick deletes nothing.
///
/// [requestedDate] is what the CLIENT believes today is, from the screen's
/// `?date=` query parameter -- distinct from [date], which exists only for
/// tests to freeze what the SERVER treats as today. When given and it no
/// longer matches, the day has turned over since the screen last loaded and
/// the tick is refused before any write, rather than filed under the new day
/// or rejected as HABIT_NOT_TODAY with no way to retry.
async function setCheck(pool, userId, habitId, done, date = null, requestedDate = null) {
  const { day, weekday } = await resolveDay(pool, date);
  if (requestedDate !== null && requestedDate !== day) {
    throw AppError.conflict('DAY_CHANGED', 'A new day has started.');
  }

  const [rows] = await pool.query(
    `SELECT 1 FROM routine_habits
      WHERE habit_id = ? AND user_id = ? AND is_active = TRUE`,
    [habitId, userId],
  );
  if (rows.length === 0) return null;
  const weekdays = (await weekdaysFor(pool, [habitId])).get(habitId);
  if (!weekdays.includes(weekday)) {
    throw AppError.badRequest('HABIT_NOT_TODAY', 'This habit does not repeat today.');
  }
  if (done) {
    await pool.query(
      'INSERT IGNORE INTO routine_checks (habit_id, check_date) VALUES (?, ?)',
      [habitId, day],
    );
  } else {
    await pool.query(
      'DELETE FROM routine_checks WHERE habit_id = ? AND check_date = ?',
      [habitId, day],
    );
  }
  return { done };
}

module.exports = {
  readDay, readHabit, createHabit, updateHabit, deactivateHabit, setCheck,
};
