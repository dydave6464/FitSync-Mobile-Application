'use strict';
const { load } = require('./src/config');
const { createLogger } = require('./src/lib/logger');
const { createPool } = require('./src/db/pool');
const { createMlService } = require('./src/services/ml');
const { createStorage } = require('./src/services/storage');
const { createGoogleVerifier } = require('./src/services/google');
const { createMailService } = require('./src/services/mail');
const { createApp } = require('./src/app');
const { assertSchemaCurrent } = require('./src/db/migrate');

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

let server;

// Before listen, not after: a server that is already accepting requests while
// this resolves would answer some of them from a schema it is about to refuse
// to run against.
async function start() {
  await assertSchemaCurrent(config.db);
  server = app.listen(config.port, () => {
    logger.info(`FitSync API listening on port ${config.port} (${config.env})`);
  });
}

start().catch((err) => {
  // Logged as a bare message rather than a stack: the whole point is that an
  // operator reads what to run, and a stack trace buries it.
  logger.error(err.message);
  pool.end().finally(() => process.exit(1));
});

let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info(`${signal} received, shutting down`);
  // A signal can arrive while the schema check is still in flight, before
  // anything is listening.
  if (!server) {
    pool.end().finally(() => process.exit(0));
    return;
  }
  server.close(() => {
    pool.end().finally(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
