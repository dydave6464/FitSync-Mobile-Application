'use strict';
const AppError = require('../lib/app-error');

module.exports = function notFound(req, _res, next) {
  next(AppError.notFound('NOT_FOUND', `No route matches ${req.method} ${req.originalUrl}`));
};
