'use strict';
const bcrypt = require('bcryptjs');

// 10 is bcryptjs's default and is a reasonable cost for a pure-JS
// implementation. Raising it makes every login measurably slower.
const ROUNDS = 10;

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

module.exports = { hashPassword, verifyPassword, DUMMY_HASH };
