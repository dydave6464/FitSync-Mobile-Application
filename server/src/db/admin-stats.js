'use strict';
const { isProSql } = require('./pro');
const { manilaDay } = require('../lib/manila-day');
const { proRevenueByMonth, adRevenueByMonth } = require('./revenue');

/// Every dated row a trainee leaves by using the app, one (user_id, d) per
/// row: a trainee is "active" on a day when any of these falls on it. Rows
/// can be dated ahead (a planned workout), so readers bound d by today.
const ACTIVITY_DAYS_SQL = `
  SELECT user_id, session_date AS d FROM workout_sessions
  UNION ALL SELECT user_id, log_date FROM meal_logs
  UNION ALL SELECT user_id, log_date FROM activity_logs
  UNION ALL SELECT user_id, log_date FROM body_weight_logs
  UNION ALL SELECT user_id, checkin_date FROM morning_checkins`;

const SIGNUP_DAYS = 30;

/// 'YYYY-MM' of the month before [ym].
function previousMonth(ym) {
  const [y, m] = ym.split('-').map(Number);
  return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`;
}

/// The numbers on the admin Overview (Appendix A, GET /admin/overview).
/// [today] is the Manila day the windows end on; the pool's sessions run at
/// +08:00, so created_at compares against it as a Manila date too.
async function overview(pool, today = manilaDay()) {
  const now = new Date(`${today}T12:00:00+08:00`);
  const windowStart = manilaDay(29, now);
  const previousStart = manilaDay(59, now);
  const previousEnd = manilaDay(30, now);

  const [[active]] = await pool.query(
    `SELECT COUNT(DISTINCT CASE WHEN a.d >= ? THEN a.user_id END) AS current_count,
            COUNT(DISTINCT CASE WHEN a.d <= ? THEN a.user_id END) AS previous_count
       FROM (${ACTIVITY_DAYS_SQL}) a
      WHERE a.d BETWEEN ? AND ?`,
    [windowStart, previousEnd, previousStart, today],
  );

  const [[pro]] = await pool.query(`SELECT COUNT(*) AS n FROM users u WHERE ${isProSql('u')}`);

  const [signupRows] = await pool.query(
    `SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS day, COUNT(*) AS n
       FROM users
      WHERE created_at >= ? AND created_at < DATE_ADD(?, INTERVAL 1 DAY)
      GROUP BY day`,
    [windowStart, today],
  );
  const byDay = new Map(signupRows.map((r) => [r.day, Number(r.n)]));
  const days = Array.from({ length: SIGNUP_DAYS }, (_, i) => {
    const date = manilaDay(SIGNUP_DAYS - 1 - i, now);
    return { date, count: byDay.get(date) || 0 };
  });

  const thisMonth = today.slice(0, 7);
  const lastMonth = previousMonth(thisMonth);
  const months = [lastMonth, thisMonth];
  const [proByMonth, adsByMonth] = await Promise.all([
    proRevenueByMonth(pool, months),
    adRevenueByMonth(pool, months),
  ]);

  return {
    today,
    activeUsers: { count: Number(active.current_count), previousCount: Number(active.previous_count) },
    proMembers: Number(pro.n),
    proRevenue: { thisMonthPhp: proByMonth.get(thisMonth), lastMonthPhp: proByMonth.get(lastMonth) },
    adRevenue: { thisMonthPhp: adsByMonth.get(thisMonth), lastMonthPhp: adsByMonth.get(lastMonth) },
    signups: { total: days.reduce((sum, d) => sum + d.count, 0), days },
  };
}

module.exports = { ACTIVITY_DAYS_SQL, overview, previousMonth };
