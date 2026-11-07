'use strict';
const { isProSql, proStatus } = require('./pro');
const { manilaDay } = require('../lib/manila-day');
const { likePattern } = require('../lib/query-params');
const { proRevenueByMonth, adRevenueByMonth, previousMonth } = require('./revenue');

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

/// Each of [userIds]' latest activity day up to [today] ('YYYY-MM-DD'), as
/// a Map; a trainee with none is absent. A row dated ahead (a planned
/// workout) is not activity yet.
async function lastActiveDays(pool, userIds, today) {
  if (userIds.length === 0) return new Map();
  const [rows] = await pool.query(
    `SELECT a.user_id, DATE_FORMAT(MAX(a.d), '%Y-%m-%d') AS day
       FROM (${ACTIVITY_DAYS_SQL}) a
      WHERE a.user_id IN (?) AND a.d <= ?
      GROUP BY a.user_id`,
    [userIds, today],
  );
  return new Map(rows.map((r) => [r.user_id, r.day]));
}

const USER_FILTERS = {
  all: null,
  pro: isProSql('u'),
  suspended: 'u.suspended_at IS NOT NULL',
};

/// One page of trainees for the admin Users tab, newest sign-ups first.
/// [q] matches name or email anywhere, ignoring case (blank or null: everyone);
/// [filter] is a USER_FILTERS key. Account summary only -- nothing a trainee
/// logged about their health.
async function listUsers(pool, { q = null, filter = 'all', page = 1, limit = 30 }, today = manilaDay()) {
  const where = [];
  const params = [];
  if (q !== null && q.trim() !== '') {
    const pattern = likePattern(q);
    where.push('(u.full_name LIKE ? OR u.email LIKE ?)');
    params.push(pattern, pattern);
  }
  if (USER_FILTERS[filter]) where.push(USER_FILTERS[filter]);
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const [[{ total }]] = await pool.query(`SELECT COUNT(*) AS total FROM users u ${whereSql}`, params);
  const [rows] = await pool.query(
    `SELECT u.user_id, u.full_name, u.email, ${isProSql('u')} AS is_pro,
            u.suspended_at IS NOT NULL AS suspended,
            DATE_FORMAT(u.created_at, '%Y-%m-%d') AS joined_on
       FROM users u ${whereSql}
      ORDER BY u.created_at DESC, u.user_id DESC
      LIMIT ? OFFSET ?`,
    [...params, limit, (page - 1) * limit],
  );
  const lastActive = await lastActiveDays(pool, rows.map((r) => r.user_id), today);
  return {
    users: rows.map((r) => ({
      id: r.user_id,
      fullName: r.full_name,
      email: r.email,
      isPro: Boolean(r.is_pro),
      suspended: Boolean(r.suspended),
      lastActiveOn: lastActive.get(r.user_id) ?? null,
      joinedOn: r.joined_on,
    })),
    total: Number(total),
  };
}

/// One trainee's account info for the admin (Appendix A's user detail), or
/// null when there is no such trainee. Account info only, by design.
async function userDetail(pool, userId, today = manilaDay()) {
  const [[row]] = await pool.query(
    `SELECT u.user_id, u.full_name, u.email, u.email_verified,
            u.password_hash IS NOT NULL AS has_password,
            EXISTS (SELECT 1 FROM user_identities gi
                     WHERE gi.user_id = u.user_id AND gi.provider = 'google') AS has_google,
            DATE_FORMAT(u.created_at, '%Y-%m-%d') AS joined_on,
            UNIX_TIMESTAMP(u.suspended_at) AS suspended_epoch
       FROM users u WHERE u.user_id = ?`,
    [userId],
  );
  if (!row) return null;
  const [lastActive, pro] = await Promise.all([
    lastActiveDays(pool, [row.user_id], today),
    proStatus(pool, row.user_id),
  ]);
  const signInMethods = [];
  if (row.has_password) signInMethods.push('password');
  if (row.has_google) signInMethods.push('google');
  return {
    id: row.user_id,
    fullName: row.full_name,
    email: row.email,
    joinedOn: row.joined_on,
    emailVerified: Boolean(row.email_verified),
    signInMethods,
    lastActiveOn: lastActive.get(row.user_id) ?? null,
    pro: { isPro: pro.pro, source: pro.source, until: pro.until },
    suspendedAt: row.suspended_epoch == null ? null : new Date(Number(row.suspended_epoch) * 1000).toISOString(),
  };
}

/// Suspends the trainee: stamps suspended_at and moves token_version on, so
/// every token on every phone stops at once. Already suspended: nothing
/// changes (the first time and the token generation stay). False when there
/// is no such trainee.
async function suspendUser(pool, userId) {
  const [r] = await pool.query(
    `UPDATE users SET suspended_at = NOW(), token_version = token_version + 1
      WHERE user_id = ? AND suspended_at IS NULL`, [userId]);
  if (r.affectedRows === 1) return true;
  return userExists(pool, userId);
}

/// Lifts a suspension; the trainee signs in again as normal. Nothing else
/// changes, and every row they logged was kept throughout. False when there
/// is no such trainee.
async function reinstateUser(pool, userId) {
  await pool.query('UPDATE users SET suspended_at = NULL WHERE user_id = ?', [userId]);
  return userExists(pool, userId);
}

async function userExists(pool, userId) {
  const [[row]] = await pool.query('SELECT 1 AS ok FROM users WHERE user_id = ?', [userId]);
  return Boolean(row);
}

module.exports = {
  ACTIVITY_DAYS_SQL,
  USER_FILTERS,
  overview,
  previousMonth,
  listUsers,
  userDetail,
  suspendUser,
  reinstateUser,
};
