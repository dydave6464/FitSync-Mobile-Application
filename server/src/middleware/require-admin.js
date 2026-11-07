'use strict';
const AppError = require('../lib/app-error');
const { verifyAdminToken } = require('../lib/admin-tokens');
const { findAdminById } = require('../db/admins');

/// Every /api/v1/admin/* route sits behind this. Only an admin token passes
/// (lib/admin-tokens.js: its own key, so a trainee token never does), and only
/// while its admins row still exists, so deleting an admin signs them out.
module.exports = function requireAdmin({ pool, jwt }) {
  return async function (req, _res, next) {
    try {
      const header = req.get('authorization') || '';
      const [scheme, token] = header.split(' ');
      if (scheme !== 'Bearer' || !token) {
        throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
      }
      const { adminId } = verifyAdminToken(token, jwt);
      const admin = await findAdminById(pool, adminId);
      if (!admin) {
        throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
      }
      req.admin = { adminId, email: admin.email, fullName: admin.full_name };
      next();
    } catch (err) {
      next(err);
    }
  };
};
