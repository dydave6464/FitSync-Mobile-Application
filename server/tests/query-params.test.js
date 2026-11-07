'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parsePositiveInt, likePattern } = require('../src/lib/query-params');

const refusal = (fn) => {
  try { fn(); } catch (e) { return { status: e.status, code: e.code, details: e.details }; }
  return null;
};

test('parsePositiveInt: a missing value is the fallback', () => {
  assert.equal(parsePositiveInt('page', undefined, 1), 1);
  assert.equal(parsePositiveInt('page', '', 7), 7);
  assert.equal(parsePositiveInt('id', undefined, null), null);
});

test('parsePositiveInt: a positive integer string is that number', () => {
  assert.equal(parsePositiveInt('page', '3', 1), 3);
  assert.equal(parsePositiveInt('limit', '50', 30, 50), 50);
});

test('parsePositiveInt: zero, negatives, fractions and words are 400 INVALID_QUERY_PARAM', () => {
  for (const raw of ['0', '-1', '1.5', 'x']) {
    assert.deepEqual(refusal(() => parsePositiveInt('page', raw, 1)), {
      status: 400, code: 'INVALID_QUERY_PARAM', details: [{ field: 'page', value: raw }],
    }, raw);
  }
});

test('parsePositiveInt: over the max is 400 INVALID_QUERY_PARAM', () => {
  assert.deepEqual(refusal(() => parsePositiveInt('limit', '51', 30, 50)), {
    status: 400, code: 'INVALID_QUERY_PARAM', details: [{ field: 'limit', value: '51' }],
  });
});

test('likePattern trims, escapes LIKE wildcards and the escape character, and wraps in %', () => {
  assert.equal(likePattern(' a%b_c\\ '), '%a\\%b\\_c\\\\%');
  assert.equal(likePattern('juan'), '%juan%');
});
