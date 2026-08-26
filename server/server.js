'use strict';
const { load } = require('./src/config');
const { createLogger } = require('./src/lib/logger');
const { createPool } = require('./src/db/pool');
const { createMlService } = require('./src/services/ml');
const { createStorage } = require('./src/services/storage');
const { createApp } = require('./src/app');

const config = load();
const logger = createLogger({ level: config.logLevel, env: config.env });
const pool = createPool(config.db);
const ml = createMlService(config.ml);
const storage = createStorage(config.storage);

const app = createApp({ config, logger, pool, ml, storage });

const server = app.listen(config.port, () => {
  logger.info(`FitSync API listening on port ${config.port} (${config.env})`);
});

function shutdown(signal) {
  logger.info(`${signal} received, shutting down`);
  server.close(() => {
    pool.end().finally(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
