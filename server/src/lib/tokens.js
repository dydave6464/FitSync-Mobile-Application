'use strict';
const jwt = require('jsonwebtoken');
const AppError = require('./app-error');

/// [tokenVersion] is the account's token generation (users.token_version)
/// as read in the same row the caller authenticated against; requireAuth
/// accepts the token only while it is still the current one.
function signToken(userId, jwtConfig, tokenVersion = 0) {
  return jwt.sign({ tv: tokenVersion }, jwtConfig.secret, {
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
  // requireAuth compares this with users.token_version. A token signed
  // before generations existed has no claim: it belongs to generation 0,
  // where every account starts.
  const tokenVersion = payload.tv === undefined ? 0 : payload.tv;
  if (!Number.isSafeInteger(tokenVersion) || tokenVersion < 0) {
    throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
  }
  return { userId, tokenVersion };
}

module.exports = { signToken, verifyToken };
