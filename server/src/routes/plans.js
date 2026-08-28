'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const { getActivePlan } = require('../db/plans');

module.exports = function buildPlansRouter(deps) {
  const router = express.Router();
  router.get('/active', requireAuth(deps), async (req, res, next) => {
    try {
      // Null rather than 404: "you have no plan yet" is a normal state during
      // onboarding, not a missing resource.
      res.json({ data: { plan: await getActivePlan(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });
  return router;
};
