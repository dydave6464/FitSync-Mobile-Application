'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const {
  invalidAdminField, idParam, searchParam, pagingParams,
} = require('../lib/admin-params');
const {
  overview, listUsers, userDetail, suspendUser, reinstateUser, USER_FILTERS,
} = require('../db/admin-stats');

function noSuchTrainee() {
  return AppError.notFound('USER_NOT_FOUND', 'No such trainee.');
}

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

  router.get('/users', async (req, res, next) => {
    try {
      const q = searchParam(req.query.q);
      // A repeated key arrives as an array (Express 5's query parser).
      const { filter = 'all' } = req.query;
      if (typeof filter !== 'string' || !Object.hasOwn(USER_FILTERS, filter)) {
        throw invalidAdminField('filter', 'filter must be all, pro or suspended.');
      }
      const { page, limit } = pagingParams(req.query);
      const { users, total } = await listUsers(pool, { q, filter, page, limit });
      res.json({ data: { users, page, limit, total } });
    } catch (err) {
      next(err);
    }
  });

  router.get('/users/:id', async (req, res, next) => {
    try {
      const userId = idParam(req.params.id);
      const user = userId === null ? null : await userDetail(pool, userId);
      if (!user) throw noSuchTrainee();
      res.json({ data: { user } });
    } catch (err) {
      next(err);
    }
  });

  // Repeat calls are harmless: each answers the trainee as they now are.
  for (const [action, apply] of [['suspend', suspendUser], ['reinstate', reinstateUser]]) {
    router.post(`/users/:id/${action}`, async (req, res, next) => {
      try {
        const userId = idParam(req.params.id);
        if (userId === null || !(await apply(pool, userId))) throw noSuchTrainee();
        // Null when the account was deleted just after the change.
        const user = await userDetail(pool, userId);
        if (!user) throw noSuchTrainee();
        res.json({ data: { user } });
      } catch (err) {
        next(err);
      }
    });
  }

  return router;
}

module.exports = { buildAdminUsersRouter };
