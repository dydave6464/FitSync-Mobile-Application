'use strict';
const crypto = require('node:crypto');

// A verification link proves someone can read mail at an address. A reset link
// hands over an account. Both are therefore treated as credentials:
//
//  - only SHA-256 of the value is stored, never the value. A leaked table
//    yields nothing usable, for the same reason password_hash is a hash.
//  - single use, enforced by consumed_at inside the consuming UPDATE.
//  - purpose-bound, so a verification token cannot be spent as a reset.
//
// See the design, section 4.

const RESET_TTL_SECONDS = 60 * 60;
const TTL_SECONDS = Object.freeze({
  verify_email: 24 * 60 * 60,
  // Deliberately far shorter. An outstanding reset token is a live account
  // takeover; an outstanding verification token is not.
  reset_password: RESET_TTL_SECONDS,
  // The web deletion page's emailed link: as destructive as a reset, so the
  // same short life.
  delete_account: RESET_TTL_SECONDS,
});

/// SHA-256, hex. Exported because shared_reports.token_hash holds the same
/// class of credential under the same policy -- one hashing helper, not two.
const hashToken = (token) => crypto.createHash('sha256').update(token).digest('hex');

async function issueToken(pool, { userId, purpose }) {
  const ttl = TTL_SECONDS[purpose];
  if (!ttl) throw new Error(`Unknown token purpose: ${purpose}`);

  const token = crypto.randomBytes(32).toString('hex');
  await pool.query(
    `INSERT INTO auth_tokens (token_hash, user_id, purpose, expires_at)
     VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))`,
    [hashToken(token), userId, purpose, ttl],
  );
  return token;
}

/// The owner of a live (unspent, unexpired) [token] for [purpose], without
/// spending it -- for a page that shows the token's form before the POST
/// that consumes it. `{ userId }` or null.
async function findLiveToken(pool, { token, purpose }) {
  if (typeof token !== 'string' || token.length === 0) return null;
  const [rows] = await pool.query(
    `SELECT user_id FROM auth_tokens
      WHERE token_hash = ? AND purpose = ? AND consumed_at IS NULL AND expires_at > NOW()`,
    [hashToken(token), purpose],
  );
  return rows.length === 0 ? null : { userId: rows[0].user_id };
}

async function consumeToken(pool, { token, purpose }) {
  if (typeof token !== 'string' || token.length === 0) return null;

  // Consume with a conditional UPDATE rather than SELECT-then-UPDATE: the
  // affectedRows count is what makes single use atomic. Two simultaneous
  // requests with the same link cannot both see it unconsumed.
  const [result] = await pool.query(
    `UPDATE auth_tokens SET consumed_at = NOW()
      WHERE token_hash = ? AND purpose = ?
        AND consumed_at IS NULL AND expires_at > NOW()`,
    [hashToken(token), purpose],
  );
  if (result.affectedRows !== 1) return null;

  const [rows] = await pool.query(
    'SELECT user_id FROM auth_tokens WHERE token_hash = ?', [hashToken(token)],
  );
  // The UPDATE above reported success, so this row existed a moment ago. If
  // the owning user were deleted in that window, ON DELETE CASCADE would
  // have removed it too -- treat that the same as any other unusable token
  // rather than throwing, to honour the "returns null" contract.
  if (rows.length === 0) return null;
  const userId = rows[0].user_id;

  if (purpose === 'reset_password') {
    // A password has just changed hands. Any other outstanding reset link for
    // this account is now a loose key to a door whose lock just changed.
    await pool.query(
      `UPDATE auth_tokens SET consumed_at = NOW()
        WHERE user_id = ? AND purpose = 'reset_password' AND consumed_at IS NULL`,
      [userId],
    );
  }
  return { userId };
}

module.exports = {
  issueToken, findLiveToken, consumeToken, hashToken, TTL_SECONDS,
};
