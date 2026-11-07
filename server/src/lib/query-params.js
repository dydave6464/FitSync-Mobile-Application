'use strict';
const AppError = require('./app-error');

// A client sending nonsense should learn that it did, rather than have the
// value silently clamped and get results it did not ask for.
function parsePositiveInt(name, raw, fallback, max = null) {
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 1) {
    throw AppError.badRequest(
      'INVALID_QUERY_PARAM',
      `${name} must be a positive integer.`,
      [{ field: name, value: String(raw) }],
    );
  }
  if (max !== null && value > max) {
    throw AppError.badRequest(
      'INVALID_QUERY_PARAM',
      `${name} must not exceed ${max}.`,
      [{ field: name, value: String(raw) }],
    );
  }
  return value;
}

/// A `LIKE ?` value matching [q] anywhere: trimmed, with `\`, `%` and `_`
/// escaped (MySQL's default LIKE escape is `\`), so "50%" finds "50%" and
/// not everything.
function likePattern(q) {
  return `%${q.trim().replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
}

module.exports = { parsePositiveInt, likePattern };
