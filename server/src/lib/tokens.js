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
    payload = jwt.verify(token, jwtConfig.secret);
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
  return { userId };
}

module.exports = { signToken, verifyToken };
