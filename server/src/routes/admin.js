'use strict';
const express = require('express');
const requireAdmin = require('../middleware/require-admin');
const { buildAdminUsersRouter } = require('./admin-users');
const { buildAdminContentRouter } = require('./admin-content');
const { buildAdminAdsRouter } = require('./admin-ads');

// The row carries password_hash. Nothing outside this module may see it.
function toPublicAdmin(row) {
  return { id: row.admin_id, email: row.email, fullName: row.full_name };
}

/// /api/v1/admin: the admin dashboard's API. Every route is behind
/// requireAdmin; the areas (users, content, ads, revenue) mount their own
/// routers here.
function buildAdminRouter(deps) {
  const router = express.Router();
  router.use(requireAdmin(deps));

  // requireAdmin has just read the admins row; req.admin is that row's
  // public part (toPublicAdmin's shape), so there is nothing more to look up.
  router.get('/me', (req, res) => {
    const { adminId, email, fullName } = req.admin;
    res.json({ data: { admin: { id: adminId, email, fullName } } });
  });

  router.use(buildAdminUsersRouter(deps));
  router.use(buildAdminContentRouter(deps));
  router.use(buildAdminAdsRouter(deps));

  return router;
}

module.exports = { buildAdminRouter, toPublicAdmin };
