'use strict';
const express = require('express');
const buildHealthRouter = require('./health');
const buildExercisesRouter = require('./exercises');

module.exports = function buildRoutes(deps = {}) {
  const router = express.Router();
  router.use('/health', buildHealthRouter(deps));
  router.use('/exercises', buildExercisesRouter(deps));
  if (deps.extraRouter) router.use(deps.extraRouter);
  return router;
};
