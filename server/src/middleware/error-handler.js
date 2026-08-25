'use strict';
const AppError = require('../lib/app-error');

module.exports = function errorHandler(logger) {
  return function handle(err, req, res, _next) {
    if (err instanceof AppError) {
      logger.warn({ reqId: req.id, code: err.code, status: err.status }, err.message);
      return res.status(err.status).json({
        error: { code: err.code, message: err.message, details: err.details },
      });
    }

    logger.error({ reqId: req.id, err }, 'unhandled error');
    return res.status(500).json({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred.',
        details: [],
      },
    });
  };
};
