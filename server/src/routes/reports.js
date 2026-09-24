'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  createSharedReport, readSharedReport, SHARE_TTL_DAYS,
} = require('../db/shared-reports');
const { buildReportSnapshot } = require('../db/report-snapshot');
const { SUMMARY_WINDOWS, periodDays } = require('../db/sessions');
const { renderPage, escapeHtml } = require('./auth-pages');
const { manilaDay } = require('../lib/manila-day');

/// One section of the report, or nothing when it was never captured.
function section(title, rows) {
  if (!rows || rows.length === 0) return '';
  const items = rows
    .map(([label, value]) => `<tr><td>${escapeHtml(label)}</td><td>${escapeHtml(value)}</td></tr>`)
    .join('');
  return `<h2>${escapeHtml(title)}</h2><table>${items}</table>`;
}

/// Kilograms the way the app writes them: 48200 is unreadable, 48.2k is not.
///
/// Mirrors formatWeightCompact in client/lib/core/units.dart. Kilograms
/// regardless of the sharer's weight-unit preference, as every other figure
/// on this page already is.
function compactKg(kg) {
  const value = Math.round(kg ?? 0);
  if (value < 1000) return `${value} kg`;
  return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}k kg`;
}

/// Volume as a DIRECTION. The total lives one section up, in the summary.
///
/// readVolumeChange in src/db/analytics.js documents `totalKg` as the half
/// that says nothing -- it swings by 50x between week and year -- and
/// `changePct` as the half that survives, and changePct was being computed,
/// stored in report_json and then never drawn. `previousKg` goes entirely:
/// it is the comparand the percentage is already made of, it appears nowhere
/// in the app, and printing two five-figure kilogram totals side by side asks
/// the coach to do a subtraction the server has already done.
///
/// The total itself is not dropped, only moved: the app's VolumeTrendCard
/// argues, correctly, that a percentage with no total behind it is the
/// thinner half of a pair -- and a first window has no percentage at all, so
/// a direction-only section would be blank for every new account. The summary
/// row carries it, compactly, and carries it even when this section is off.
function volumeSection(period, change) {
  if (!change) return '';

  // Null means the previous window held nothing. "+100%" measured from zero
  // is not a fact about training, so say there is nothing to compare against
  // rather than print a number that reads like one.
  const pct = change.changePct;
  const value = pct === null || pct === undefined
    ? `No previous ${period} to compare against`
    : `${pct >= 0 ? '+' : ''}${pct}% against the previous ${period}`;

  return section('Training volume', [['Change', value]]);
}

function renderReport({ fullName, period, windowStart, windowEnd, report }) {
  const day = (d) => new Date(d).toISOString().slice(0, 10);
  const s = report.summary || {};

  const body = [
    `<p class="who">${escapeHtml(fullName)} &middot; ${escapeHtml(period)}` +
      ` &middot; ${escapeHtml(day(windowStart))} to ${escapeHtml(day(windowEnd))}</p>`,
    section('Summary', [
      ['Sessions', String(s.sessionCount ?? 0)],
      ['Sets', String(s.setCount ?? 0)],
      ['Volume', compactKg(s.totalVolumeKg)],
    ]),
    report.volume ? volumeSection(period, report.volume.change) : '',
    report.bodyWeight && report.bodyWeight.points.length > 0
      ? section('Body weight',
          report.bodyWeight.points.map((p) => [p.loggedOn, `${p.weightKg} kg`]))
        // The window widened to find enough points to draw -- these entries
        // fall outside the "week"/"2026-09-12 to 2026-09-19" caption above,
        // and this is the only place that says so: the coach reading this
        // page has no other context to notice on their own.
        + (report.bodyWeight.widened
            ? '<p class="note">Fewer than two entries in this window; showing all recent entries.</p>'
            : '')
      : '',
    report.muscles
      ? section('Muscle balance',
          report.muscles.map((m) => [m.muscle, `${Math.round(m.volumeKg)} kg`]))
      : '',
    report.sessions
      ? section('Sessions',
          report.sessions.map((x) => [x.sessionDate, `${x.setCount} sets`]))
      : '',
  ].join('');

  // Deliberately generic, with the name left in the body only. The designed
  // delivery path for this link is pasting it into a chat app, and chat apps
  // fetch a URL server-side to build a preview card -- which reads <title>.
  // A name in there reaches third-party infrastructure before anyone has
  // opened the link at all, and X-Robots-Tag does nothing about unfurlers.
  return renderPage({ title: 'Training report', body });
}

module.exports = function buildReportsRouter(deps = {}) {
  const router = express.Router();
  const auth = requireAuth(deps);
  const publicBaseUrl = deps.publicBaseUrl || 'http://localhost:3000';

  router.post('/', auth, async (req, res, next) => {
    try {
      const period = req.body.period || 'week';
      // periodDays, not a bare SUMMARY_WINDOWS[period]: the object inherits
      // from Object.prototype, so period='constructor' would read a function
      // off the prototype chain, sail past the !days check and reach the
      // query as a bind parameter -- a 500 where this 400 is the answer.
      const days = periodDays(period);
      if (!days) {
        throw AppError.badRequest(
          'INVALID_PERIOD',
          `period must be one of ${Object.keys(SUMMARY_WINDOWS).join(', ')}.`,
        );
      }

      const report = await buildReportSnapshot(deps.pool, req.user.userId, {
        period,
        include: req.body.include,
        premium: req.user.isPremium,
      });

      const { token, expiresAt } = await createSharedReport(deps.pool, req.user.userId, {
        period,
        windowStart: manilaDay(days),
        windowEnd: manilaDay(),
        report,
      });

      res.status(201).json({
        data: {
          url: `${publicBaseUrl}/api/v1/reports/${token}`,
          expiresAt,
        },
      });
    } catch (err) { next(err); }
  });

  // No auth: the token IS the credential. That is the whole point -- a coach
  // opens this without an account.
  router.get('/:token', async (req, res, next) => {
    try {
      const found = await readSharedReport(deps.pool, req.params.token);

      // A pasted link must not reach a search index.
      res.set('X-Robots-Tag', 'noindex, nofollow');

      // Server-side expiry is the only lifetime guarantee this feature has,
      // and a browser or shared proxy holding a cached copy would outlive it
      // silently. Set before the branch, so the 404 an expired link gets is
      // not itself cached over a link that is about to come back as a 200 for
      // nobody. auth.js does the same for the reset form.
      res.set('Cache-Control', 'no-store');

      if (!found) {
        // Byte-identical to the page an expired link gets, so this never
        // confirms whether a token was real.
        res.status(404).send(renderPage({
          title: 'Report unavailable',
          // The TTL read from the one place that sets it, so this sentence
          // cannot quietly start lying the day it changes.
          body: `<p>This report is no longer available. Links expire `
              + `${SHARE_TTL_DAYS} days after they are shared.</p>`,
        }));
        return;
      }

      res.status(200).send(renderReport(found));
    } catch (err) { next(err); }
  });

  return router;
};
