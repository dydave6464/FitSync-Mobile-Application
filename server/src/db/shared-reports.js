'use strict';
const crypto = require('node:crypto');

/// How long a shared link stays open.
///
/// Fixed at creation rather than applied on read, so a link's lifetime is the
/// one that was in force when the user shared it.
const SHARE_TTL_DAYS = 30;

/// 32 bytes of CSPRNG, base64url -- 43 characters.
///
/// This token is the ONLY credential the report page has: there is no sign-in
/// on the reading end. It is never derived from a user id, a row id or a
/// timestamp, because all three are guessable from outside.
function mintToken() {
  return crypto.randomBytes(32).toString('base64url');
}

async function createSharedReport(pool, userId, { period, windowStart, windowEnd, report }) {
  const token = mintToken();
  await pool.query(
    `INSERT INTO shared_reports
       (user_id, token, period, window_start, window_end, report_json, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? DAY))`,
    [userId, token, period, windowStart, windowEnd, JSON.stringify(report), SHARE_TTL_DAYS],
  );

  const [[row]] = await pool.query(
    'SELECT expires_at FROM shared_reports WHERE token = ?', [token],
  );
  return { token, expiresAt: row.expires_at };
}

/// Null for a token that does not exist AND for one that has expired.
///
/// Deliberately the same answer: the caller renders one page for both, so the
/// endpoint never confirms whether a token was ever real.
async function readSharedReport(pool, token) {
  const [[row]] = await pool.query(
    `SELECT r.user_id, r.period, r.window_start, r.window_end, r.report_json,
            r.expires_at, u.full_name
       FROM shared_reports r
       JOIN users u ON u.user_id = r.user_id
      WHERE r.token = ? AND r.expires_at > NOW()`,
    [token],
  );
  if (!row) return null;

  return {
    userId: row.user_id,
    // Read live rather than from the snapshot: a renamed user should not have
    // their old name sitting on a link that still works.
    fullName: row.full_name,
    period: row.period,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    // mysql2 returns JSON columns already parsed on some driver versions and
    // as a string on others.
    report: typeof row.report_json === 'string'
      ? JSON.parse(row.report_json)
      : row.report_json,
    expiresAt: row.expires_at,
  };
}

module.exports = { createSharedReport, readSharedReport, SHARE_TTL_DAYS };
