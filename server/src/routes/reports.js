'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { createSharedReport, readSharedReport } = require('../db/shared-reports');
const { buildReportSnapshot } = require('../db/report-snapshot');
const { SUMMARY_WINDOWS } = require('../db/sessions');
const { renderPage, escapeHtml } = require('./auth-pages');

/// YYYY-MM-DD, `days` before today, in the server's LOCAL time.
///
/// Local getters throughout, and deliberately NOT toISOString(): that reads
/// the date back out in UTC, which east of Greenwich returns yesterday for
/// the first hours of every local day. These bounds caption a report whose
/// data was windowed by MySQL CURDATE() -- the server's local date -- so the
/// two must share a basis or the caption contradicts the numbers.
function localDay(daysBack = 0) {
  const d = new Date();
  d.setDate(d.getDate() - daysBack);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/// One section of the report, or nothing when it was never captured.
function section(title, rows) {
  if (!rows || rows.length === 0) return '';
  const items = rows
    .map(([label, value]) => `<tr><td>${escapeHtml(label)}</td><td>${escapeHtml(value)}</td></tr>`)
    .join('');
  return `<h2>${escapeHtml(title)}</h2><table>${items}</table>`;
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
      ['Volume', `${Math.round(s.totalVolumeKg ?? 0)} kg`],
    ]),
    report.volume
      ? section('Training volume', [
          ['Total', `${Math.round(report.volume.change.totalKg)} kg`],
          ['Previous window', `${Math.round(report.volume.change.previousKg)} kg`],
        ])
      : '',
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

  return renderPage({ title: `Training report — ${fullName}`, body });
}

module.exports = function buildReportsRouter(deps = {}) {
  const router = express.Router();
  const auth = requireAuth(deps);
  const publicBaseUrl = deps.publicBaseUrl || 'http://localhost:3000';

  router.post('/', auth, async (req, res, next) => {
    try {
      const period = req.body.period || 'week';
      const days = SUMMARY_WINDOWS[period];
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
        windowStart: localDay(days),
        windowEnd: localDay(),
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

      if (!found) {
        // Byte-identical to the page an expired link gets, so this never
        // confirms whether a token was real.
        res.status(404).send(renderPage({
          title: 'Report unavailable',
          body: '<p>This report is no longer available. Links expire 30 days '
              + 'after they are shared.</p>',
        }));
        return;
      }

      res.status(200).send(renderReport(found));
    } catch (err) { next(err); }
  });

  return router;
};
