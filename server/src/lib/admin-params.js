'use strict';
const AppError = require('./app-error');
const { parsePositiveInt } = require('./query-params');

// The admin dashboard's lists: 30 rows a page unless asked, never over 50.
const DEFAULT_LIMIT = 30;
const MAX_LIMIT = 50;

/// 400 INVALID_ADMIN_FIELD for [field], every admin route's refusal shape.
function invalidAdminField(field, message) {
  return AppError.badRequest('INVALID_ADMIN_FIELD', message, [{ field }]);
}

/// The :id of an admin route, or null when it can't name a row (then the
/// answer is the same 404 as an unknown id).
function idParam(raw) {
  return /^[1-9]\d{0,9}$/.test(raw) ? Number(raw) : null;
}

/// A single search text ('' when absent), or a 400: a repeated key arrives
/// as an array (Express 5's query parser).
function searchParam(raw) {
  if (raw === undefined) return '';
  if (typeof raw !== 'string') throw invalidAdminField('q', 'q must be a single search text.');
  return raw;
}

/// The page and limit of an admin list's query (400 INVALID_QUERY_PARAM when
/// either isn't a positive integer, or the limit is over MAX_LIMIT).
function pagingParams(query) {
  return {
    page: parsePositiveInt('page', query.page, 1),
    limit: parsePositiveInt('limit', query.limit, DEFAULT_LIMIT, MAX_LIMIT),
  };
}

module.exports = {
  DEFAULT_LIMIT, MAX_LIMIT, invalidAdminField, idParam, searchParam, pagingParams,
};
