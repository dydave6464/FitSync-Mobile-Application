'use strict';
const { issueToken, consumeToken } = require('../lib/auth-tokens');

/// Account deletion (spec 2026-11-06-account-deletion). Every table holding
/// a user's data references users(user_id) ON DELETE CASCADE, so deleting
/// the users row removes all of it -- profile, training, nutrition, payments,
/// sign-in identities and emailed tokens. InnoDB runs the cascade inside the
/// DELETE statement itself: it all goes or none of it does. Nothing on disk
/// belongs to a user (server files are only shared exercise media).

/// The one deletion, used by the app route and the web page alike. [db] is
/// the pool or a connection inside a caller's transaction. True when the
/// account existed.
async function deleteUser(db, userId) {
  const [result] = await db.query('DELETE FROM users WHERE user_id = ?', [userId]);
  return result.affectedRows === 1;
}

/// The web page's confirm: spends the emailed [token] and deletes its
/// account in one transaction, so a failed delete leaves the link usable
/// rather than spent. Two clicks at once cannot both pass: the consuming
/// UPDATE locks the token row until this commits. The deleted account's id,
/// or null for a dead link (unknown, expired, spent or another purpose's).
async function deleteUserByToken(pool, token) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const found = await consumeToken(conn, { token, purpose: 'delete_account' });
    const deleted = found !== null && await deleteUser(conn, found.userId);
    await conn.commit();
    return deleted ? found.userId : null;
  } catch (err) {
    await conn.rollback().catch(() => {});
    throw err;
  } finally {
    conn.release();
  }
}

/// Whether [subject] is the Google identity linked to [userId] -- the app's
/// "Confirm with Google" must be this account's own Google account.
async function isGoogleIdentityOf(pool, userId, subject) {
  const [rows] = await pool.query(
    `SELECT 1 FROM user_identities
      WHERE user_id = ? AND provider = 'google' AND provider_subject = ?`,
    [userId, subject],
  );
  return rows.length > 0;
}

// The request page mails whoever's address is typed, with no sign-in, so it
// is held to the password reset's limits: one link a minute and ten a day per
// account. Anyone can make the page mail an account's owner; nobody can
// flood them with it.
const RESEND_COOLDOWN_SECONDS = 60;
const DAILY_LINK_LIMIT = 10;

/// A new delete link for [userId], or null when the account asked for one
/// within the last minute or has had DAILY_LINK_LIMIT in a day. The users
/// row is locked while counting, so two requests at once cannot both pass.
async function issueDeleteLink(pool, userId) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE', [userId]);
    const [[recent]] = await conn.query(
      `SELECT COUNT(*) AS today,
              COALESCE(MAX(created_at) > DATE_SUB(NOW(), INTERVAL ? SECOND), 0) AS fresh
         FROM auth_tokens
        WHERE user_id = ? AND purpose = 'delete_account'
          AND created_at > DATE_SUB(NOW(), INTERVAL 1 DAY)`,
      [RESEND_COOLDOWN_SECONDS, userId],
    );
    const token = Number(recent.fresh) === 1 || Number(recent.today) >= DAILY_LINK_LIMIT
      ? null
      : await issueToken(conn, { userId, purpose: 'delete_account' });
    await conn.commit();
    return token;
  } catch (err) {
    await conn.rollback().catch(() => {});
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = {
  deleteUser, deleteUserByToken, isGoogleIdentityOf, issueDeleteLink,
  RESEND_COOLDOWN_SECONDS, DAILY_LINK_LIMIT,
};
