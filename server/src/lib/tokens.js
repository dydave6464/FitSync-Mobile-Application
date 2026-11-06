'use strict';
const jwt = require('jsonwebtoken');
const AppError = require('./app-error');

function signToken(userId, jwtConfig) {
  return jwt.sign({}, jwtConfig.secret, {
    subject: String(userId),
    expiresIn: jwtConfig.expiresIn,
  });
}

function verifyToken(token, jwtConfig) {
  let payload;
  try {
    // Pin algorithms to HS256. Although this secret is a random string (not a
    // public key), algorithm-confusion attacks are eliminated by restricting
    // to the algorithm we use.
    payload = jwt.verify(token, jwtConfig.secret, { algorithms: ['HS256'] });
  } catch (cause) {
    // A bad signature, an expired token and malformed input are all the same
    // to a caller: this request is not authenticated. Saying which would tell
    // an attacker whether they had the shape right.
    throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
  }
  const userId = Number(payload.sub);
  if (!Number.isSafeInteger(userId) || userId < 1) {
    throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
  }
  // requireAuth compares this with the user's sign-out cutoff
  // (users.tokens_valid_after). Every token signToken issues carries one; a
  // token without one could never be shown to postdate a cutoff.
  const issuedAt = payload.iat;
  if (!Number.isSafeInteger(issuedAt)) {
    throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
  }
  return { userId, issuedAt };
}

module.exports = { signToken, verifyToken };
