'use strict';
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const requestId = require('./middleware/request-id');
const notFound = require('./middleware/not-found');
const errorHandler = require('./middleware/error-handler');
const buildRoutes = require('./routes');

function createApp({ config, logger, pool, ml = null, storage = null, extraRouter = null }) {
  const app = express();

  app.disable('x-powered-by');
  app.use(helmet());
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));
  app.use(requestId);

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

  app.use('/api/v1', buildRoutes({ config, logger, pool, ml, storage, extraRouter }));

  app.use(notFound);
  app.use(errorHandler(logger));

  return app;
}

module.exports = { createApp };
