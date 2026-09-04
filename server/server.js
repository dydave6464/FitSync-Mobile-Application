'use strict';
const { load } = require('./src/config');
const { createLogger } = require('./src/lib/logger');
const { createPool } = require('./src/db/pool');
const { createMlService } = require('./src/services/ml');
const { createStorage } = require('./src/services/storage');
const { createGoogleVerifier } = require('./src/services/google');
const { createMailService } = require('./src/services/mail');
const { createApp } = require('./src/app');

const config = load();
const logger = createLogger({ level: config.logLevel, env: config.env });
const pool = createPool(config.db);
const ml = createMlService(config.ml);
const storage = createStorage(config.storage);
const google = createGoogleVerifier(config.google);
const mail = createMailService(config.mail, logger);

const app = createApp({
  config, logger, pool, ml, storage, jwt: config.jwt, google,
  mail, publicBaseUrl: config.publicBaseUrl,
});

const server = app.listen(config.port, () => {
  logger.info(`FitSync API listening on port ${config.port} (${config.env})`);
});

let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info(`${signal} received, shutting down`);
  server.close(() => {
    pool.end().finally(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
