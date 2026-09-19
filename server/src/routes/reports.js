'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { createSharedReport } = require('../db/shared-reports');
const { buildReportSnapshot } = require('../db/report-snapshot');
const { SUMMARY_WINDOWS } = require('../db/sessions');

/// YYYY-MM-DD, `days` before today, in the server's local time -- the same
/// basis session_date is stamped and compared on.
function windowStart(days) {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().slice(0, 10);
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
        windowStart: windowStart(days),
        windowEnd: new Date().toISOString().slice(0, 10),
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
