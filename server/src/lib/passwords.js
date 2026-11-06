'use strict';
const bcrypt = require('bcryptjs');
const AppError = require('./app-error');

// 10 is bcryptjs's default and is a reasonable cost for a pure-JS
// implementation. Raising it makes every login measurably slower.
const ROUNDS = 10;

// The password length rule, one home for every route that takes a password.
const MIN_PASSWORD_LENGTH = 8;
// bcrypt (via bcryptjs) only reads the first 72 bytes of its input — anything
// beyond that contributes nothing to the hash. Without a cap, an anonymous
// caller can send an arbitrarily large password and force the server to spend
// real CPU running it through a deliberately slow hash function: a cheap
// denial-of-service against the one route that has no auth to gate it.
const MAX_PASSWORD_LENGTH = 72;

async function hashPassword(plain) {
  return bcrypt.hash(plain, ROUNDS);
}

async function verifyPassword(plain, hash) {
  // Google-only accounts have a NULL password_hash. bcrypt.compare throws on
  // null, so the guard keeps the login route from 500ing on a real case.
  if (!hash) return false;
  return bcrypt.compare(plain, hash);
}

// A precomputed hash of a value nobody will ever type, at the same cost as a
// real password hash. The login route compares against this whenever there is
// no real hash to check (unknown email, or a Google-only account with a NULL
// password_hash), so every login pays the same bcrypt cost. Skipping the
// compare in those cases would let response latency reveal which case it was
// — exactly the account-existence signal INVALID_CREDENTIALS's identical
// code and message exist to hide. Do not "optimise" this away.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', ROUNDS);

/// The signed-in user re-confirms their password: before changing it
/// (POST /auth/password) or deleting the account (POST /account/delete). One
/// check, so the two can never disagree about the same password.
///
/// Trimmed like login's, so it compares against the hash register made. One
/// answer for anything that is not the password -- missing, non-string, blank
/// or over-length included, since register never stored such a password.
/// Those skip bcrypt, so the cap keeps its work bounded. Resolves on a match,
/// else throws 400 WRONG_PASSWORD, which the app shows under the field.
async function confirmPassword(typed, hash) {
  const plain = typeof typed === 'string' ? typed.trim() : '';
  const matches = plain.length > 0 && plain.length <= MAX_PASSWORD_LENGTH
    && await verifyPassword(plain, hash);
  if (!matches) {
    throw AppError.badRequest('WRONG_PASSWORD', "That password isn't right.");
  }
}

module.exports = {
  hashPassword, verifyPassword, confirmPassword, DUMMY_HASH,
  MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH,
};
