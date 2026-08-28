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

function buildTestApp(deps = {}) {
  const { pool = null, extend = null, storage = null, storageConfig = null } = deps;
  const extraRouter = express.Router();
  if (extend) extend(extraRouter);

  return createApp({
    config: { env: 'test', logLevel: 'silent', storage: storageConfig },
    logger: silentLogger(),
    pool,
    storage,
    extraRouter: extend ? extraRouter : null,
    jwt: deps.jwt || { secret: 'test-secret-value-at-least-32-chars', expiresIn: '30d' },
    google: deps.google || require('../../src/services/google').createGoogleVerifier({ mode: 'stub' }),
  });
}

module.exports = { buildTestApp, silentLogger };
