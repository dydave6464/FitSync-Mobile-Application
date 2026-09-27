'use strict';
const {
  generateCode, hashCode, sameHash, TTL_MINUTES, MAX_ATTEMPTS, LOCKOUT_MINUTES,
  RESEND_COOLDOWN_SECONDS,
} = require('../lib/auth-codes');

/// A new code for [userId] and [purpose], replacing any earlier one, or null
/// when the last one was issued less than a minute ago -- the resend limit --
/// or when the user is locked out: the last code took MAX_ATTEMPTS wrong
/// guesses and its lockout (until expires_at) has not ended. Without that,
/// asking for a new code would undo the attempt limit. A lockout that has
/// ended is replaced like any older code.
/// Uses row-level locking to ensure only one request succeeds if called
/// simultaneously for the same user+purpose. Returns null if another request
/// issued a code at the same moment (answers the same as the resend limit).
/// The caller answers the same either way; only the email is held back.
async function issueCode(pool, { key, userId, purpose }) {
  const ttl = TTL_MINUTES[purpose];
  if (!ttl) throw new Error(`Unknown code purpose: ${purpose}`);

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[row]] = await conn.query(
      `SELECT created_at > DATE_SUB(NOW(), INTERVAL ? SECOND) AS fresh,
              attempts >= ? AND expires_at > NOW() AS locked
         FROM auth_codes WHERE user_id = ? AND purpose = ? FOR UPDATE`,
      [RESEND_COOLDOWN_SECONDS, MAX_ATTEMPTS, userId, purpose],
    );

    if (row) {
      if (Number(row.locked) === 1 || Number(row.fresh) === 1) {
        await conn.commit();
        return null;
      }
      // Row exists but is older (or its lockout has ended), update it
      const code = generateCode();
      await conn.query(
        `UPDATE auth_codes SET code_hash = ?, expires_at = DATE_ADD(NOW(), INTERVAL ? MINUTE),
                              attempts = 0, created_at = NOW() WHERE user_id = ? AND purpose = ?`,
        [hashCode(key, { userId, purpose, code }), ttl, userId, purpose],
      );
      await conn.commit();
      return code;
    } else {
      // No row exists, insert new one
      const code = generateCode();
      await conn.query(
        `INSERT INTO auth_codes (user_id, purpose, code_hash, expires_at, attempts, created_at)
         VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? MINUTE), 0, NOW())`,
        [userId, purpose, hashCode(key, { userId, purpose, code }), ttl],
      );
      await conn.commit();
      return code;
    }
  } catch (err) {
    await conn.rollback();
    if (err.code === 'ER_DUP_ENTRY' || err.code === 'ER_LOCK_DEADLOCK') {
      return null;
    }
    throw err;
  } finally {
    conn.release();
  }
}

/// Whether [code] is the live code for [userId] and [purpose]. A match is
/// consumed. A miss counts an attempt; the fifth does not delete the code but
/// turns its row into a lockout: attempts stays at MAX_ATTEMPTS and expires_at
/// moves to LOCKOUT_MINUTES from now, so issueCode refuses a new code until
/// then. A locked code fails every check, the right code included, and is left
/// untouched. An expired code, locked or not, is deleted. One locked row per
/// check, so two guesses at once cannot both be counted as the first.
async function checkCode(pool, { key, userId, purpose, code }) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[row]] = await conn.query(
      `SELECT code_hash, attempts, expires_at > NOW() AS live
         FROM auth_codes WHERE user_id = ? AND purpose = ? FOR UPDATE`,
      [userId, purpose],
    );
    const remove = () => conn.query(
      'DELETE FROM auth_codes WHERE user_id = ? AND purpose = ?', [userId, purpose],
    );

    let ok = false;
    if (!row) {
      ok = false;
    } else if (Number(row.live) !== 1) {
      await remove();
    } else if (row.attempts >= MAX_ATTEMPTS) {
      ok = false; // locked out: no guess counts, not even the right one
    } else if (sameHash(row.code_hash, hashCode(key, { userId, purpose, code }))) {
      await remove();
      ok = true;
    } else if (row.attempts + 1 >= MAX_ATTEMPTS) {
      await conn.query(
        `UPDATE auth_codes SET attempts = ?, expires_at = DATE_ADD(NOW(), INTERVAL ? MINUTE)
          WHERE user_id = ? AND purpose = ?`,
        [MAX_ATTEMPTS, LOCKOUT_MINUTES, userId, purpose],
      );
    } else {
      await conn.query(
        'UPDATE auth_codes SET attempts = attempts + 1 WHERE user_id = ? AND purpose = ?',
        [userId, purpose],
      );
    }
    await conn.commit();
    return ok;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = { issueCode, checkCode };
