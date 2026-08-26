'use strict';
const express = require('express');
const { createApp } = require('../../src/app');
const { createLogger } = require('../../src/lib/logger');

function silentLogger() {
  // A real pino instance at the 'silent' level: emits nothing, but (unlike a
  // hand-rolled noop stub) still satisfies pino-http's expectations of a
  // genuine logger (e.g. `.levels.values`, a working `.child()`).
  return createLogger({ level: 'silent', env: 'test' });
}

function buildTestApp({ pool = null, extend = null } = {}) {
  const extraRouter = express.Router();
  if (extend) extend(extraRouter);

  return createApp({
    config: { env: 'test', logLevel: 'silent' },
    logger: silentLogger(),
    pool,
    extraRouter: extend ? extraRouter : null,
  });
}

module.exports = { buildTestApp, silentLogger };
