'use strict';
const express = require('express');
const buildHealthRouter = require('./health');

module.exports = function buildRoutes(deps) {
  const router = express.Router();
  router.use('/health', buildHealthRouter(deps));
  if (deps.extraRouter) router.use(deps.extraRouter);
  return router;
};
