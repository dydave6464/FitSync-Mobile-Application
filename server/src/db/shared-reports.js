'use strict';
const crypto = require('node:crypto');
const { hashToken } = require('../lib/auth-tokens');

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

/// Mints a token, stores only its hash, and hands the plaintext back once.
///
/// The caller needs the plaintext to build the URL; the database never sees
/// it. This is the policy 011_email_verification.sql already states for
/// auth_tokens -- an outstanding share token is 30 days of access to a named
/// person's training data, so a leaked table must yield nothing usable. It is
/// also why nothing else in this module reads a token back out: there is
/// nothing to read.
async function createSharedReport(pool, userId, { period, windowStart, windowEnd, report }) {
  const token = mintToken();

  // Computed here in epoch seconds and written with FROM_UNIXTIME, rather
  // than computed by MySQL and read back with a second SELECT.
  //
  // That SELECT was both a wasted round trip and WRONG. expires_at is a
  // TIMESTAMP, which MySQL renders in the session's time zone on the way out,
  // and the pool's `timezone: 'Z'` then labels that local wall clock as UTC --
  // it cannot undo a conversion the server already did. On this Asia/Manila
  // host the expiry handed to the client came back eight hours later than the
  // one the server actually enforces. src/db/sessions.js documents the same
  // trap for started_at and reaches for the same remedy: speak to MySQL in
  // epoch seconds, which no time zone touches in either direction.
  //
  // Seconds, not milliseconds, so the value returned is byte-for-byte the
  // instant the column holds rather than up to a second ahead of it.
  const expiresAtEpoch = Math.floor(Date.now() / 1000) + SHARE_TTL_DAYS * 24 * 60 * 60;

  await pool.query(
    `INSERT INTO shared_reports
       (user_id, token_hash, period, window_start, window_end, report_json, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))`,
    [userId, hashToken(token), period, windowStart, windowEnd,
      JSON.stringify(report), expiresAtEpoch],
  );

  return { token, expiresAt: new Date(expiresAtEpoch * 1000) };
}

/// Null for a token that does not exist AND for one that has expired.
///
/// Deliberately the same answer: the caller renders one page for both, so the
/// endpoint never confirms whether a token was ever real.
async function readSharedReport(pool, token) {
  if (typeof token !== 'string' || token.length === 0) return null;

  const [[row]] = await pool.query(
    `SELECT r.user_id, r.period, r.window_start, r.window_end, r.report_json,
            UNIX_TIMESTAMP(r.expires_at) AS expires_at_epoch, u.full_name
       FROM shared_reports r
       JOIN users u ON u.user_id = r.user_id
      WHERE r.token_hash = ? AND r.expires_at > NOW()`,
    [hashToken(token)],
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
    // UNIX_TIMESTAMP for the same reason createSharedReport uses it: a plain
    // SELECT of a TIMESTAMP is out by the server's whole UTC offset.
    expiresAt: new Date(Number(row.expires_at_epoch) * 1000),
  };
}

module.exports = { createSharedReport, readSharedReport, SHARE_TTL_DAYS };
