'use strict';
const express = require('express');
const buildHealthRouter = require('./health');
const buildExercisesRouter = require('./exercises');
const buildAuthRouter = require('./auth');
const buildProfileRouter = require('./profile');
const buildPlansRouter = require('./plans');
const requireAuth = require('../middleware/require-auth');

module.exports = function buildRoutes(deps = {}) {
  const router = express.Router();
  router.use('/health', buildHealthRouter(deps));
  router.use('/auth', buildAuthRouter(deps));
  router.use(buildProfileRouter(deps));
  router.use('/plans', buildPlansRouter(deps));
  // The catalogue is reference data, but the app requires sign-in to reach any
  // of it, so an open endpoint would just be an inconsistency.
  router.use('/exercises', requireAuth(deps), buildExercisesRouter(deps));
  if (deps.extraRouter) router.use(deps.extraRouter);
  return router;
};
