'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const { readStreak } = require('../db/streak');

module.exports = function buildStreakRouter(deps) {
  const router = express.Router();

  router.get('/', requireAuth(deps), async (req, res, next) => {
    try {
      res.json({ data: await readStreak(deps.pool, req.user.userId) });
    } catch (err) { next(err); }
  });

  return router;
};
