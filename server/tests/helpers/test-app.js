'use strict';
const express = require('express');
const { createApp } = require('../../src/app');

function silentLogger() {
  const noop = () => {};
  return { info: noop, warn: noop, error: noop, debug: noop, child: () => silentLogger() };
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
