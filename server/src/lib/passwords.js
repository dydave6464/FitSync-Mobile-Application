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

module.exports = { hashPassword, verifyPassword };
