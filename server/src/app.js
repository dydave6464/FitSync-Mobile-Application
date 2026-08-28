'use strict';
const path = require('node:path');
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const pinoHttp = require('pino-http');
const requestId = require('./middleware/request-id');
const notFound = require('./middleware/not-found');
const errorHandler = require('./middleware/error-handler');
const buildRoutes = require('./routes');

function createApp({
  config, logger, pool, ml = null, storage = null, extraRouter = null, jwt = null, google = null,
}) {
  const app = express();

  app.disable('x-powered-by');
  app.use(helmet());
  app.use(cors());
  app.use(requestId);
  app.use(pinoHttp({ logger, genReqId: (req) => req.id }));
  app.use(express.json({ limit: '1mb' }));

  app.use((req, _res, next) => {
    req.services = {
      pool,
      ml,
      storage,
      logger,
      config: config
        ? {
            env: config.env,
            port: config.port,
            logLevel: config.logLevel,
            ml: config.ml ? { mode: config.ml.mode } : null,
            storage: config.storage ? { mode: config.storage.mode } : null,
          }
        : null,
    };
    next();
  });

  // Media lives outside /api/v1 because storage.url(key) returns '/storage/<key>'
  // and that contract predates this route. express.static brings tested path
  // handling, range requests and caching headers. Default fallthrough is kept so
  // a missing file reaches notFound and gets the standard error envelope rather
  // than an HTML page.
  if (config && config.storage && config.storage.mode === 'local') {
    app.use(
      '/storage',
      express.static(path.resolve(config.storage.localDir || 'storage'), {
        maxAge: '1h',
        index: false,
        dotfiles: 'deny',
      }),
    );
  }

  app.use('/api/v1', buildRoutes({ config, logger, pool, ml, storage, extraRouter, jwt, google }));

  app.use(notFound);
  app.use(errorHandler(logger));

  return app;
}

module.exports = { createApp };
