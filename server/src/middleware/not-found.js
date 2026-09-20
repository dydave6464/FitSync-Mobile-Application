'use strict';
const AppError = require('../lib/app-error');
const { redactUrl } = require('../lib/redact-url');

module.exports = function notFound(req, _res, next) {
  // originalUrl goes into a message error-handler.js logs at warn level, so
  // it needs the same redaction the request logger applies. A share link
  // pasted with one stray trailing character -- /api/v1/reports/<token>/x --
  // misses the route, lands here, and would otherwise write a live 30-day
  // credential into the logs on its way to a 404.
  next(AppError.notFound(
    'NOT_FOUND',
    `No route matches ${req.method} ${redactUrl(req.originalUrl)}`,
  ));
};
