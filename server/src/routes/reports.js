'use strict';
const express = require('express');
const helmet = require('helmet');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  createSharedReport, readSharedReport, SHARE_TTL_DAYS,
} = require('../db/shared-reports');
const { buildReportSnapshot } = require('../db/report-snapshot');
const { SUMMARY_WINDOWS, periodDays } = require('../db/sessions');
const { manilaDay } = require('../lib/manila-day');
const {
  renderReportPage, renderReportUnavailable, PRINT_SCRIPT,
} = require('../lib/report-page');

module.exports = function buildReportsRouter(deps = {}) {
  const router = express.Router();
  const auth = requireAuth(deps);
  const publicBaseUrl = deps.publicBaseUrl || 'http://localhost:3000';

  // helmet's CSP minus upgrade-insecure-requests, for the same reason as
  // routes/pro.js (the stub checkout) and routes/account.js (the delete
  // pages): on the phone hotspot's plain http that directive turns the
  // page's <script src=".../print.js"> into an https request that fails, and
  // the Print button never appears. script-src 'self' and the rest stay.
  // Over https it changes nothing.
  const pagePolicy = helmet.contentSecurityPolicy({
    useDefaults: true,
    directives: { upgradeInsecureRequests: null },
  });

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
        // N days ending today, today included: the first is N - 1 days ago.
        windowStart: manilaDay(days - 1),
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

  // The Print button's script. A file rather than inline because helmet's CSP
  // allows script from 'self' only. Registered before /:token so it is never
  // looked up as a report.
  router.get('/print.js', (req, res) => {
    res.set('Cache-Control', 'public, max-age=3600');
    res.type('application/javascript').send(PRINT_SCRIPT);
  });

  // No auth: the token IS the credential. That is the whole point -- a coach
  // opens this without an account.
  router.get('/:token', pagePolicy, async (req, res, next) => {
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
        // confirms whether a token was real. The TTL is read from the one
        // place that sets it.
        res.status(404).send(renderReportUnavailable(SHARE_TTL_DAYS));
        return;
      }

      res.status(200).send(renderReportPage(found));
    } catch (err) { next(err); }
  });

  return router;
};
