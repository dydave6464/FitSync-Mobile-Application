'use strict';
const express = require('express');
const { invalidAdminField } = require('../lib/admin-params');
const { manilaDay } = require('../lib/manila-day');
const { revenueMonth } = require('../db/revenue');

/// The ?month of GET /revenue: this Manila month when absent; a real
/// YYYY-MM no later than [thisMonth], or a 400. A repeated key arrives as an
/// array (Express 5's query parser), which is a 400 too.
function monthParam(raw, thisMonth) {
  if (raw === undefined) return thisMonth;
  if (typeof raw !== 'string' || !/^\d{4}-(0[1-9]|1[0-2])$/.test(raw) || raw > thisMonth) {
    throw invalidAdminField('month', 'month must be this month or an earlier one, as YYYY-MM.');
  }
  return raw;
}

/// The admin Revenue area. Mounted inside buildAdminRouter, so every route
/// here is already behind requireAdmin.
function buildAdminRevenueRouter({ pool }) {
  const router = express.Router();

  router.get('/revenue', async (req, res, next) => {
    try {
      const today = manilaDay();
      const month = monthParam(req.query.month, today.slice(0, 7));
      res.json({ data: await revenueMonth(pool, month, today) });
    } catch (err) {
      next(err);
    }
  });

  return router;
}

module.exports = { buildAdminRevenueRouter };
