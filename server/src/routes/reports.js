'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { createSharedReport } = require('../db/shared-reports');
const { buildReportSnapshot } = require('../db/report-snapshot');
const { SUMMARY_WINDOWS } = require('../db/sessions');

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

  return router;
};
