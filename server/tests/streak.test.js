'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { computeStreak } = require('../src/lib/streak');

// 2026-09-21 is a Monday, so 2026-09-24 is a Thursday.
const TODAY = '2026-09-24';

test('no activity: no streak', () => {
  const s = computeStreak([], TODAY);
  assert.equal(s.current, 0);
  assert.equal(s.best, 0);
  assert.equal(s.todayActive, false);
});

test('active today only: one day', () => {
  const s = computeStreak(['2026-09-24'], TODAY);
  assert.equal(s.current, 1);
  assert.equal(s.best, 1);
  assert.equal(s.todayActive, true);
});

test('nothing yet today: the run through yesterday still stands', () => {
  const s = computeStreak(['2026-09-22', '2026-09-23'], TODAY);
  assert.equal(s.current, 2);
  assert.equal(s.todayActive, false);
});

test('a missed yesterday ends it', () => {
  const s = computeStreak(['2026-09-21', '2026-09-22'], TODAY);
  assert.equal(s.current, 0);
  assert.equal(s.best, 2);
});

test('today extends the run through yesterday', () => {
  assert.equal(computeStreak(['2026-09-22', '2026-09-23', '2026-09-24'], TODAY).current, 3);
});

test('a gap splits runs: current is the latest, best the longest', () => {
  const s = computeStreak(
    ['2026-09-10', '2026-09-11', '2026-09-12', '2026-09-13', '2026-09-23', '2026-09-24'],
    TODAY,
  );
  assert.equal(s.current, 2);
  assert.equal(s.best, 4);
});

test('a run crosses a month end', () => {
  assert.equal(computeStreak(['2026-08-31', '2026-09-01'], '2026-09-01').current, 2);
});

test('the same date twice counts once', () => {
  const s = computeStreak(['2026-09-24', '2026-09-24'], TODAY);
  assert.equal(s.current, 1);
  assert.equal(s.best, 1);
});

test('the week is Monday to Sunday around today; later days are never active', () => {
  assert.deepEqual(computeStreak(['2026-09-21', '2026-09-23', '2026-09-24'], TODAY).week, [
    { date: '2026-09-21', active: true },
    { date: '2026-09-22', active: false },
    { date: '2026-09-23', active: true },
    { date: '2026-09-24', active: true },
    { date: '2026-09-25', active: false },
    { date: '2026-09-26', active: false },
    { date: '2026-09-27', active: false },
  ]);
});

test('on a Monday the week starts today; on a Sunday it ends today', () => {
  const monday = computeStreak([], '2026-09-21').week;
  assert.equal(monday[0].date, '2026-09-21');
  assert.equal(monday[6].date, '2026-09-27');
  const sunday = computeStreak([], '2026-09-27').week;
  assert.equal(sunday[0].date, '2026-09-21');
  assert.equal(sunday[6].date, '2026-09-27');
});
