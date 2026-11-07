'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { isRealDay } = require('../src/lib/days');

test('isRealDay: a real calendar day as YYYY-MM-DD', () => {
  for (const v of ['2026-11-07', '2024-02-29', '2030-12-31', '1999-01-01']) assert.equal(isRealDay(v), true, v);
});

test('isRealDay: anything else is false', () => {
  for (const v of [
    '2026-02-30', '2025-02-29', '2026-13-01', '2026-00-10', '2026-11-00', '2026-1-01', '2026-11-7',
    ' 2026-11-07', '2026-11-07T00:00:00Z', 'tomorrow', '', undefined, null, 20261107, ['2026-11-07'],
  ]) assert.equal(isRealDay(v), false, JSON.stringify(v));
});
