'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  renderReportPage, renderReportUnavailable, PRINT_SCRIPT, PRINT_SCRIPT_PATH,
  compactKg, bucketName,
} = require('../src/lib/report-page');

// test66's month report, as stored on 2026-11-09 (trimmed).
const monthReport = () => ({
  summary: {
    setCount: 75, sessionCount: 13, totalVolumeKg: 31243.5,
    adherence: { done: 13, weeks: 4, target: 13 },
  },
  volume: {
    buckets: [
      { label: '-25d', volumeKg: 3550.5 }, { label: '-20d', volumeKg: 5404.5 },
      { label: '-15d', volumeKg: 7308 }, { label: '-10d', volumeKg: 5539.5 },
      { label: '-5d', volumeKg: 3793.5 }, { label: 'now', volumeKg: 5647.5 },
    ],
    change: { totalKg: 31243.5, previousKg: 25800, changePct: 21 },
  },
  bodyWeight: {
    widened: false,
    points: [
      { loggedOn: '2026-10-16', weightKg: 76.4 }, { loggedOn: '2026-10-23', weightKg: 76 },
      { loggedOn: '2026-10-30', weightKg: 75.6 }, { loggedOn: '2026-11-06', weightKg: 75.2 },
    ],
  },
  muscles: [{ muscle: 'delts', volumeKg: 4200 }, { muscle: 'quads', volumeKg: 2100 }],
  sessions: [{
    planName: 'Demo week 1', setCount: 3, sessionId: 164, startedAt: null, durationMin: 45,
    sessionDate: '2026-11-08', muscleGroups: [], exerciseCount: 4, totalVolumeKg: 1930.5,
  }],
});

const page = (overrides = {}) => renderReportPage({
  fullName: 'Test SixtySix',
  period: 'month',
  windowStart: '2026-10-11',
  windowEnd: '2026-11-09',
  expiresAt: new Date('2026-12-09T05:00:00Z'),
  report: monthReport(),
  ...overrides,
});

test('the title stays generic and the name sits in the body', () => {
  const html = page();
  assert.equal(html.match(/<title>([^<]*)<\/title>/)[1], 'Training report');
  assert.match(html, /Test SixtySix · Oct 11 – Nov 9, 2026 · Month/);
  assert.match(html, /class="brand">FitSync</);
});

test('the tiles show volume, sessions of planned, sets and the weight change', () => {
  const html = page();
  assert.match(html, /31\.2k kg/);
  assert.match(html, /\+21% vs previous month/);
  assert.match(html, /of 13 planned/);
  assert.match(html, /<p class="v num">75<\/p>/);
  assert.match(html, /−1\.2 kg/);
  assert.match(html, /76\.4 → 75\.2/);
});

test('a plan with no target shows sessions without "of N planned"', () => {
  const report = monthReport();
  report.summary.adherence.target = null;
  assert.ok(!page({ report }).includes('planned'));
});

test('no volume percentage without a previous window', () => {
  const report = monthReport();
  report.volume.change.changePct = null;
  const html = page({ report });
  assert.ok(!html.includes('vs previous'));
  assert.match(html, /No previous month to compare against/);
});

test('the weight tile needs two points inside the window', () => {
  const one = monthReport();
  one.bodyWeight.points = one.bodyWeight.points.slice(0, 1);
  assert.ok(!page({ report: one }).includes('→'));

  const widened = monthReport();
  widened.bodyWeight.widened = true;
  const html = page({ report: widened });
  assert.ok(!html.includes('76.4 → 75.2'));
  assert.match(html, /Fewer than two entries in this window; showing all recent entries\./);
});

test('a section switched off is absent', () => {
  const report = { ...monthReport(), volume: null, bodyWeight: null, muscles: null, sessions: null };
  const html = page({ report });
  for (const heading of ['Training volume', 'Body weight', 'Muscle balance', 'Sessions</h2>']) {
    assert.ok(!html.includes(heading), `${heading} should be absent`);
  }
  // The summary tiles are always there.
  assert.match(html, /31\.2k kg/);
});

test('a section included but empty says so', () => {
  const report = {
    ...monthReport(),
    bodyWeight: { widened: false, points: [] },
    muscles: [],
    sessions: [],
    volume: { buckets: [{ label: 'now', volumeKg: 0 }], change: null },
  };
  const html = page({ report });
  assert.match(html, /No weigh-ins in this period/);
  assert.match(html, /No sessions in this period/);
  assert.match(html, /No training volume in this month/);
  assert.match(html, /Muscle balance/);
});

test('session rows read as a day, a plan and their figures', () => {
  const html = page();
  assert.match(html, /Sun, Nov 8 · Demo week 1/);
  assert.match(html, /4 exercises · 3 sets · 45 min · 1\.9k kg/);
});

test('an old snapshot without plan name or duration still renders', () => {
  const report = monthReport();
  report.sessions = [{ sessionDate: '2026-11-08', setCount: 1 }];
  const html = page({ report });
  assert.match(html, /Sun, Nov 8 · Workout/);
  assert.match(html, />1 set</);
  // Not includes('min'): the CSS has min-height and minmax.
  assert.ok(!/\d+ min\b/.test(html), 'no duration invented');
});

test('the footer names the frozen day and the expiry', () => {
  assert.match(page(), /Frozen on Nov 9, 2026 · This link works until Dec 9, 2026/);
});

test('hostile strings are escaped', () => {
  const report = monthReport();
  report.sessions[0].planName = '<img src=x onerror=alert(1)>';
  report.muscles[0].muscle = '<b>delts</b>';
  const html = page({ fullName: '<script>alert(1)</script>', report });
  assert.ok(!html.includes('<script>alert(1)</script>'));
  assert.ok(!html.includes('<img src=x'));
  assert.ok(!html.includes('<b>delts</b>'));
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
});

test('the page loads nothing from outside and has no inline script', () => {
  const html = page();
  assert.ok(!/https?:\/\//.test(html), 'no absolute URL of any kind');
  assert.ok(!/<script(?![^>]*\bsrc=)[^>]*>/.test(html), 'no inline script body');
  assert.ok(!/\son[a-z]+=/i.test(html), 'no inline event handlers');
  assert.match(html, new RegExp(`<script src="${PRINT_SCRIPT_PATH}" defer></script>`));
  assert.match(html, /<button type="button" class="print" id="print" hidden>Print \/ Save as PDF<\/button>/);
  assert.match(html, /Use your browser's Print to save this as a PDF\./);
});

test('dark mode and print styles are present', () => {
  const html = page();
  assert.match(html, /@media \(prefers-color-scheme: dark\)/);
  assert.match(html, /@media print/);
});

test('the print script reveals the button and prints', () => {
  assert.match(PRINT_SCRIPT, /window\.print\(\)/);
  assert.match(PRINT_SCRIPT, /getElementById\('print'\)/);
});

test('the unavailable page keeps its wording and loads no script', () => {
  const html = renderReportUnavailable(30);
  assert.match(html, /This report is no longer available\. Links expire 30 days after they are shared\./);
  assert.equal(html.match(/<title>([^<]*)<\/title>/)[1], 'Report unavailable');
  assert.ok(!html.includes('<script'));
});

test('compactKg writes thousands compactly', () => {
  assert.equal(compactKg(950), '950 kg');
  assert.equal(compactKg(48200), '48.2k kg');
  assert.equal(compactKg(3000), '3k kg');
  assert.equal(compactKg(null), '0 kg');
});

test('chart bars are named the way the app names them, from the frozen day', () => {
  const end = new Date(Date.UTC(2026, 10, 9)); // Mon, Nov 9 2026
  // A week: one bar a day, named by weekday.
  assert.deepEqual(
    bucketName({ period: 'week', index: 6, count: 7, fallback: 'today', end }),
    { axis: 'Mon', full: 'Mon, Nov 9' },
  );
  assert.equal(bucketName({ period: 'week', index: 0, count: 7, fallback: '-6d', end }).axis, 'Tue');
  // A month: six five-day spans, named by the day each ends.
  assert.deepEqual(
    bucketName({ period: 'month', index: 5, count: 6, fallback: 'now', end }),
    { axis: 'Nov 9', full: 'Nov 5 – Nov 9' },
  );
  assert.equal(bucketName({ period: 'month', index: 0, count: 6, fallback: '-25d', end }).full, 'Oct 11 – Oct 15');
  // A year: every other month name, newest always named.
  assert.equal(bucketName({ period: 'year', index: 11, count: 12, fallback: 'now', end }).axis, 'Oct');
  assert.equal(bucketName({ period: 'year', index: 10, count: 12, fallback: '-1m', end }).axis, '');
  // An unknown period keeps the server's label.
  assert.deepEqual(
    bucketName({ period: 'decade', index: 0, count: 3, fallback: '-2x', end }),
    { axis: '-2x', full: '-2x' },
  );
});

test('the chart writes each bar value as text', () => {
  const html = page();
  assert.match(html, /<svg class="chart"/);
  assert.match(html, />7\.3k</);
  assert.match(html, /<title>Oct 21 – Oct 25: 7\.3k kg<\/title>/);
});
