'use strict';
const AppError = require('../lib/app-error');

// mysql2 attaches the fully-interpolated SQL string to every error it raises
// — as err.sql, with bound parameters already substituted in, and often again
// inside err.sqlMessage for a constraint violation. pino's default error
// serializer logs every own enumerable property of an Error, so passing a
// mysql2 error straight to logger.error(...) below would put whatever was
// bound into that query — including a bcrypt password hash on a failed
// INSERT INTO users — into the log output in plaintext. src/lib/logger.js's
// redact list only catches the *key* password_hash; it cannot see a hash
// embedded inside an arbitrary SQL string, so this cannot be fixed there.
// err.code, err.errno and err.sqlState carry none of that risk and stay —
// they are exactly what makes a mysql2 failure diagnosable from logs. Do NOT
// re-add sql/sqlMessage here for debugging convenience; use a local
// reproduction against a real error instead.
function sanitizeForLogging(err) {
  if (!err || typeof err !== 'object') return err;
  if (!('sql' in err) && !('sqlMessage' in err)) return err;
  const clone = Object.create(Object.getPrototypeOf(err));
  Object.assign(clone, err);
  delete clone.sql;
  delete clone.sqlMessage;
  // Preserve stack/message/name, which live on the prototype chain for a
  // subclassed Error and would otherwise be lost by Object.assign alone.
  clone.stack = err.stack;
  clone.message = err.message;
  return clone;
}

// Non-AppError errors that carry a 4xx status come from lower-level
// middleware (body-parser, express.static/send, ...) rather than from an
// AppError.badRequest()/forbidden()/etc. call, so they need to be translated
// into the response envelope by status code. This used to map every such
// status to INVALID_REQUEST_BODY / "The request body could not be parsed" —
// written for body-parser's own 400/413 errors, but wrong for anything else
// that reaches here with a 4xx: most visibly a genuine 403 from
// express.static's dotfiles: 'deny' on a path-traversal attempt, which is a
// bodyless GET being told its (nonexistent) body could not be parsed.
const STATUS_CODES = {
  403: { code: 'FORBIDDEN', message: 'You are not permitted to access this resource.' },
  404: { code: 'NOT_FOUND', message: 'The requested resource was not found.' },
};

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
      let code;
      let message;
      if (err.type === 'entity.too.large') {
        code = 'PAYLOAD_TOO_LARGE';
        message = 'The request body is larger than allowed.';
      } else if (STATUS_CODES[status]) {
        ({ code, message } = STATUS_CODES[status]);
      } else {
        // The case this branch was originally written for: a body-parser
        // failure (400) with no more specific status mapped above.
        code = 'INVALID_REQUEST_BODY';
        message = 'The request body could not be parsed.';
      }
      logger.warn({ reqId: req.id, code, status }, err.message);
      return res.status(status).json({ error: { code, message, details: [] } });
    }

    logger.error({ reqId: req.id, err: sanitizeForLogging(err) }, 'unhandled error');
    return res.status(500).json({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred.',
        details: [],
      },
    });
  };
};
