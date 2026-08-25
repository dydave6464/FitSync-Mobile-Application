'use strict';

class AppError extends Error {
  constructor(status, code, message, details = []) {
    super(message);
    this.name = 'AppError';
    this.status = status;
    this.code = code;
    this.details = details;
    Error.captureStackTrace(this, AppError);
  }

  static badRequest(code, message, details = []) {
    return new AppError(400, code, message, details);
  }

  static unauthorized(code, message) {
    return new AppError(401, code, message);
  }

  static forbidden(code, message) {
    return new AppError(403, code, message);
  }

  static notFound(code, message) {
    return new AppError(404, code, message);
  }

  static conflict(code, message) {
    return new AppError(409, code, message);
  }
}

module.exports = AppError;
