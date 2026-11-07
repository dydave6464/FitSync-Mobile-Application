'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  invalidAdminField, idParam, searchParam, pagingParams, bodyOf, DEFAULT_LIMIT, MAX_LIMIT,
} = require('../src/lib/admin-params');

const refusal = (fn) => {
  try { fn(); } catch (e) { return { status: e.status, code: e.code, message: e.message, details: e.details }; }
  return null;
};

test('invalidAdminField is a 400 INVALID_ADMIN_FIELD naming the field', () => {
  const e = invalidAdminField('status', 'status must be pending or live.');
  assert.deepEqual(
    { status: e.status, code: e.code, message: e.message, details: e.details },
    { status: 400, code: 'INVALID_ADMIN_FIELD', message: 'status must be pending or live.', details: [{ field: 'status' }] },
  );
});

test('idParam: a positive id of up to 10 digits is that number', () => {
  assert.equal(idParam('1'), 1);
  assert.equal(idParam('4294967295'), 4294967295);
});

test('idParam: anything that cannot name a row is null', () => {
  for (const raw of ['0', '01', '-1', '1.5', 'x', '', '12345678901', ' 1']) assert.equal(idParam(raw), null, raw);
});

test('searchParam: missing is empty, one text is that text', () => {
  assert.equal(searchParam(undefined), '');
  assert.equal(searchParam(' juan '), ' juan ');
});

test('searchParam: a repeated q is 400 INVALID_ADMIN_FIELD', () => {
  assert.deepEqual(refusal(() => searchParam(['a', 'b'])), {
    status: 400, code: 'INVALID_ADMIN_FIELD', message: 'q must be a single search text.', details: [{ field: 'q' }],
  });
});

test('pagingParams: page 1 and the admin default limit when absent', () => {
  assert.deepEqual(pagingParams({}), { page: 1, limit: DEFAULT_LIMIT });
  assert.equal(DEFAULT_LIMIT, 30);
  assert.equal(MAX_LIMIT, 50);
});

test('pagingParams: reads page and limit, and refuses a limit over the max', () => {
  assert.deepEqual(pagingParams({ page: '2', limit: '50' }), { page: 2, limit: 50 });
  assert.deepEqual(refusal(() => pagingParams({ limit: '51' })), {
    status: 400, code: 'INVALID_QUERY_PARAM', message: 'limit must not exceed 50.', details: [{ field: 'limit', value: '51' }],
  });
});

test('bodyOf: a JSON object body is that object; anything else is no fields', () => {
  const b = { title: 'x' };
  assert.equal(bodyOf({ body: b }), b);
  for (const body of [undefined, null, [], ['a'], 'text', 5, true]) assert.deepEqual(bodyOf({ body }), {}, JSON.stringify(body));
});
