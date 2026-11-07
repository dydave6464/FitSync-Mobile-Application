'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const { parsePositiveInt } = require('../lib/query-params');
const {
  overview, listUsers, userDetail, suspendUser, reinstateUser, USER_FILTERS,
} = require('../db/admin-stats');

const DEFAULT_LIMIT = 30;
const MAX_LIMIT = 50;

function invalid(field, message) {
  return AppError.badRequest('INVALID_ADMIN_FIELD', message, [{ field }]);
}

function noSuchTrainee() {
  return AppError.notFound('USER_NOT_FOUND', 'No such trainee.');
}

/// The :id of a users route, or null when it can't name a trainee (then the
/// answer is the same 404 as an unknown id).
function userIdParam(raw) {
  return /^[1-9]\d{0,9}$/.test(raw) ? Number(raw) : null;
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
      const { q = '', filter = 'all' } = req.query;
      // A repeated key arrives as an array (Express 5's query parser).
      if (typeof q !== 'string') throw invalid('q', 'q must be a single search text.');
      if (typeof filter !== 'string' || !Object.hasOwn(USER_FILTERS, filter)) {
        throw invalid('filter', 'filter must be all, pro or suspended.');
      }
      const page = parsePositiveInt('page', req.query.page, 1);
      const limit = parsePositiveInt('limit', req.query.limit, DEFAULT_LIMIT, MAX_LIMIT);
      const { users, total } = await listUsers(pool, { q, filter, page, limit });
      res.json({ data: { users, page, limit, total } });
    } catch (err) {
      next(err);
    }
  });

  router.get('/users/:id', async (req, res, next) => {
    try {
      const userId = userIdParam(req.params.id);
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
        const userId = userIdParam(req.params.id);
        if (userId === null || !(await apply(pool, userId))) throw noSuchTrainee();
        res.json({ data: { user: await userDetail(pool, userId) } });
      } catch (err) {
        next(err);
      }
    });
  }

  return router;
}

module.exports = { buildAdminUsersRouter };
