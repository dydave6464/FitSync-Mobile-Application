'use strict';
const crypto = require('node:crypto');

/// Six-digit codes emailed for verification and password reset and typed into
/// the app (docs/superpowers/specs/2026-09-27-email-codes-design.md).
///
/// A code is short enough to guess, so it is guarded unlike the 64-hex link
/// tokens it replaces (lib/auth-tokens.js): a keyed hash, so a leaked table
/// cannot be brute-forced back to codes without the server secret; an attempt
/// limit and a short life (db/auth-codes.js).
///
/// The attempt limit only holds if spending it cannot be undone by asking for
/// another code. So the fifth wrong guess locks the user and purpose out for
/// LOCKOUT_MINUTES: the code stops working, even the right one, and no new code
/// is issued until the lockout ends.
///
/// That alone still allows a new code a minute, and an attacker who stops at
/// four guesses a code never meets the lockout. So no account gets more than
/// DAILY_CODE_LIMIT codes per purpose in any 24 hours. Every code allows
/// MAX_ATTEMPTS real guesses (the fifth is checked before it locks), so that
/// is at most fifty guesses a day against a million possible codes.

const TTL_MINUTES = Object.freeze({
  verify_email: 60,
  // Shorter: an outstanding reset code is a live account takeover.
  reset_password: 15,
});
const MAX_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 15;
const RESEND_COOLDOWN_SECONDS = 60;
const DAILY_CODE_LIMIT = 10;

function generateCode() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

/// The HMAC key for code hashes: derived from JWT_SECRET under its own label,
/// so this use of the secret can never stand in for signing a session.
function codeKey(secret) {
  if (typeof secret !== 'string' || secret.length === 0) {
    throw new Error('codeKey needs the JWT secret');
  }
  return crypto.createHmac('sha256', secret).update('fitsync-auth-code').digest();
}

/// Tied to the user and purpose as well as the code, so a stored hash is
/// meaningless for anyone or anything else.
function hashCode(key, { userId, purpose, code }) {
  return crypto.createHmac('sha256', key).update(`${userId}:${purpose}:${code}`).digest('hex');
}

/// Constant-time comparison of exactly the hashes hashCode produces. Returns
/// false unless both arguments are strings matching /^[a-f0-9]{64}$/ — the
/// exact format hashCode produces. This prevents Buffer.from silently truncating
/// invalid hex. Timing-safe, so how long a wrong guess takes says nothing about
/// how close it was.
function sameHash(a, b) {
  const pattern = /^[a-f0-9]{64}$/;
  if (typeof a !== 'string' || !pattern.test(a)) return false;
  if (typeof b !== 'string' || !pattern.test(b)) return false;
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return crypto.timingSafeEqual(x, y);
}

/// A code as typed or pasted -- spaces allowed -- or null when it cannot be
/// one. A null is refused before any database lookup, so it costs no attempt.
function normaliseCode(raw) {
  if (typeof raw !== 'string') return null;
  const code = raw.replace(/\s+/g, '');
  return /^\d{6}$/.test(code) ? code : null;
}

module.exports = {
  generateCode, codeKey, hashCode, sameHash, normaliseCode,
  TTL_MINUTES, MAX_ATTEMPTS, LOCKOUT_MINUTES, RESEND_COOLDOWN_SECONDS,
  DAILY_CODE_LIMIT,
};
