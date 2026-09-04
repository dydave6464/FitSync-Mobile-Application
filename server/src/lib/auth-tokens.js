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

const TTL_SECONDS = Object.freeze({
  verify_email: 24 * 60 * 60,
  // Deliberately far shorter. An outstanding reset token is a live account
  // takeover; an outstanding verification token is not.
  reset_password: 60 * 60,
});

const hash = (token) => crypto.createHash('sha256').update(token).digest('hex');

async function issueToken(pool, { userId, purpose }) {
  const ttl = TTL_SECONDS[purpose];
  if (!ttl) throw new Error(`Unknown token purpose: ${purpose}`);

  const token = crypto.randomBytes(32).toString('hex');
  await pool.query(
    `INSERT INTO auth_tokens (token_hash, user_id, purpose, expires_at)
     VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))`,
    [hash(token), userId, purpose, ttl],
  );
  return token;
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
    [hash(token), purpose],
  );
  if (result.affectedRows !== 1) return null;

  const [rows] = await pool.query(
    'SELECT user_id FROM auth_tokens WHERE token_hash = ?', [hash(token)],
  );
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

module.exports = { issueToken, consumeToken, TTL_SECONDS };
