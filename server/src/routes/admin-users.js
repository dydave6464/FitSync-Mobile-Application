'use strict';
const express = require('express');
const { overview } = require('../db/admin-stats');

/// The admin Overview and Users areas. Mounted inside buildAdminRouter, so
/// every route here is already behind requireAdmin.
function buildAdminUsersRouter({ pool }) {
  const router = express.Router();

  router.get('/overview', async (_req, res, next) => {
    try {
      res.json({ data: await overview(pool) });
    } catch (err) {
      next(err);
    }
  });

  return router;
}

module.exports = { buildAdminUsersRouter };
