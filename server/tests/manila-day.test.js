'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { manilaDay } = require('../src/lib/manila-day');

// Instants chosen either side of Manila's midnight (16:00 UTC). The suite is
// also run under TZ=UTC and TZ=America/New_York: a helper that read the
// host's own zone would return the UTC or New York date for these.
test('manilaDay is the Manila date of an instant, whatever the host zone', () => {
  const cases = [
    ['2026-09-23T15:59:00Z', 0, '2026-09-23'], // 23:59 Manila
    ['2026-09-23T16:00:00Z', 0, '2026-09-24'], // 00:00 Manila: the new day
    ['2026-09-23T16:30:00Z', 0, '2026-09-24'],
    ['2026-10-01T01:00:00Z', 1, '2026-09-30'], // back across a month end
    ['2026-09-24T02:00:00Z', 30, '2026-08-25'],
  ];
  for (const [iso, back, want] of cases) {
    assert.equal(manilaDay(back, new Date(iso)), want, `${iso} minus ${back}`);
  }
});
