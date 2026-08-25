'use strict';
const express = require('express');

module.exports = function buildRoutes({ extraRouter = null } = {}) {
  const router = express.Router();
  if (extraRouter) router.use(extraRouter);
  return router;
};
