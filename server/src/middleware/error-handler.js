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

    const status = err.status || err.statusCode;
    if (Number.isInteger(status) && status >= 400 && status < 500) {
      const code = err.type === 'entity.too.large' ? 'PAYLOAD_TOO_LARGE' : 'INVALID_REQUEST_BODY';
      const message =
        code === 'PAYLOAD_TOO_LARGE'
          ? 'The request body is larger than allowed.'
          : 'The request body could not be parsed.';
      logger.warn({ reqId: req.id, code, status }, err.message);
      return res.status(status).json({ error: { code, message, details: [] } });
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
