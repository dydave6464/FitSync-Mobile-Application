'use strict';
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const AppError = require('./app-error');

/// The admin token's signing key: derived from JWT_SECRET under its own label
/// (the auth-codes.js pattern), so a trainee token can never verify as an
/// admin's and the reverse, with no new setting.
function adminKey(secret) {
  if (typeof secret !== 'string' || secret.length === 0) throw new Error('adminKey needs the JWT secret');
  return crypto.createHmac('sha256', secret).update('fitsync-admin-token').digest();
}

function signAdminToken(adminId, jwtConfig) {
  return jwt.sign({ role: 'admin' }, adminKey(jwtConfig.secret), {
    subject: String(adminId), expiresIn: jwtConfig.expiresIn, algorithm: 'HS256',
  });
}

const unauthenticated = () => AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');

function verifyAdminToken(token, jwtConfig) {
  let payload;
  try {
    payload = jwt.verify(token, adminKey(jwtConfig.secret), { algorithms: ['HS256'] });
  } catch (_) { throw unauthenticated(); }
  const adminId = Number(payload.sub);
  if (payload.role !== 'admin' || !Number.isSafeInteger(adminId) || adminId < 1) throw unauthenticated();
  return { adminId };
}

module.exports = { adminKey, signAdminToken, verifyAdminToken };
