'use strict';
const AppError = require('../lib/app-error');
const { verifyToken } = require('../lib/tokens');
const { findUserById } = require('../db/users');

module.exports = function requireAuth({ pool, jwt }) {
  return async function (req, _res, next) {
    try {
      const header = req.get('authorization') || '';
      const [scheme, token] = header.split(' ');
      if (scheme !== 'Bearer' || !token) {
        throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
      }
      const { userId } = verifyToken(token, jwt);

      // A token can outlive its user — the account may have been deleted since
      // it was issued. Checking here means routes can trust req.user exists.
      const user = await findUserById(pool, userId);
      if (!user) {
        throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
      }

      req.user = { userId };
      next();
    } catch (err) {
      next(err);
    }
  };
};
