'use strict';
const { weekdaysFor, hhmm } = require('./routine');
const { dayNumber, dateOf } = require('../lib/streak');
const { isPlannedWorkoutDay } = require('../lib/workout-day');

/// 1 = Monday .. 7 = Sunday. Day 0 (1970-01-01) was a Thursday.
function weekdayOf(dayNo) {
  return ((dayNo + 3) % 7) + 1;
}

/// Every day from [from] to [to] inclusive ('YYYY-MM-DD', oldest first):
/// what was done on the days before today, what is planned from today on.
///
/// Before today: the day's first completed workout, named by its own plan,
/// and the habits ticked -- deleted ones included, since routine_checks is
/// kept. Past schedules were never recorded, so nothing is said about what
/// was planned then. Today: the habits due plus any ticked, and the routine's
/// workout item. After today: the active habits and the workout the current
/// weekdays and training days plan, none done.
///
/// [today] exists for tests; the route never passes it, so today is
/// CURDATE() -- Manila, as on every pooled connection. A fixed set of
/// queries whatever the range's length; the days are assembled here.
async function readCalendar(pool, userId, from, to, today = null) {
  const [[clock]] = await pool.query(
    `SELECT DATE_FORMAT(COALESCE(?, CURDATE()), '%Y-%m-%d') AS today`, [today],
  );
  const todayNo = dayNumber(clock.today);

  // Every habit the user has made, deleted ones included -- a past tick still
  // names its habit -- in the routine's order: timed by time, then untimed by
  // title. Each day lists its habits in this order.
  const [habits] = await pool.query(
    `SELECT habit_id, title, scheduled_time, is_active
       FROM routine_habits
      WHERE user_id = ?
      ORDER BY scheduled_time IS NULL, scheduled_time, title, habit_id`,
    [userId],
  );
  const weekdays = await weekdaysFor(
    pool, habits.filter((h) => h.is_active).map((h) => h.habit_id),
  );

  const [ticks] = await pool.query(
    `SELECT DATE_FORMAT(c.check_date, '%Y-%m-%d') AS d, c.habit_id
       FROM routine_checks c
       JOIN routine_habits h ON h.habit_id = c.habit_id
      WHERE h.user_id = ? AND c.check_date BETWEEN ? AND ?`,
    [userId, from, to],
  );
  const ticked = new Set(ticks.map((r) => `${r.d}#${r.habit_id}`));

  const [sessions] = await pool.query(
    `SELECT DATE_FORMAT(s.session_date, '%Y-%m-%d') AS d, p.name
       FROM workout_sessions s
       LEFT JOIN workout_plans p ON p.plan_id = s.plan_id
      WHERE s.user_id = ? AND s.status = 'completed'
        AND s.session_date BETWEEN ? AND ?
      ORDER BY s.session_date, s.session_id`,
    [userId, from, to],
  );
  const finished = new Map(); // date -> the first completed session's title
  for (const r of sessions) {
    if (!finished.has(r.d)) finished.set(r.d, r.name ?? 'Workout');
  }

  const [[plan]] = await pool.query(
    'SELECT name FROM workout_plans WHERE user_id = ? AND is_active = TRUE LIMIT 1',
    [userId],
  );
  const [chosen] = await pool.query(
    'SELECT weekday FROM user_training_days WHERE user_id = ?', [userId],
  );
  const trainingDays = chosen.map((r) => Number(r.weekday));
  const planTitle = plan ? plan.name : 'Workout';

  const days = [];
  for (let n = dayNumber(from); n <= dayNumber(to); n += 1) {
    const date = dateOf(n);
    const weekday = weekdayOf(n);
    const past = n < todayNo;
    const isToday = n === todayNo;

    let workout = null;
    if (past) {
      if (finished.has(date)) workout = { title: finished.get(date), done: true };
    } else if (isToday && finished.has(date)) {
      workout = { title: planTitle, done: true };
    } else if (isPlannedWorkoutDay({ hasActivePlan: Boolean(plan), trainingDays, weekday })) {
      workout = { title: planTitle, done: false };
    }

    const listed = [];
    for (const h of habits) {
      const done = !past && !isToday ? false : ticked.has(`${date}#${h.habit_id}`);
      const due = Boolean(h.is_active) && weekdays.get(h.habit_id).includes(weekday);
      const shown = past ? done : isToday ? done || due : due;
      if (shown) {
        listed.push({ habitId: h.habit_id, title: h.title, time: hhmm(h.scheduled_time), done });
      }
    }

    days.push({ date, workout, habits: listed });
  }
  return { today: clock.today, days };
}

module.exports = { readCalendar };
