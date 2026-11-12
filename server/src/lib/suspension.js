'use strict';
const AppError = require('./app-error');

/// The one answer for a suspended trainee (users.suspended_at set, migration
/// 044): password sign-in, Google sign-in and every authenticated request.
const SUSPENDED = () => AppError.forbidden('ACCOUNT_SUSPENDED', 'This account is suspended.');

module.exports = { SUSPENDED };
