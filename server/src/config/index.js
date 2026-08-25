'use strict';
require('dotenv').config({ quiet: true });

const REQUIRED = ['DB_HOST', 'DB_PORT', 'DB_USER', 'DB_PASSWORD', 'DB_NAME'];

function load(env = process.env) {
  const missing = REQUIRED.filter((key) => !env[key]);
  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }

  return {
    env: env.NODE_ENV || 'development',
    port: Number(env.PORT || 3000),
    logLevel: env.LOG_LEVEL || 'info',
    db: {
      host: env.DB_HOST,
      port: Number(env.DB_PORT),
      user: env.DB_USER,
      password: env.DB_PASSWORD,
      database: env.DB_NAME,
      connectionLimit: Number(env.DB_POOL_SIZE || 10),
    },
    ml: {
      mode: env.ML_MODE || 'stub',
      serviceUrl: env.ML_SERVICE_URL || null,
    },
    storage: {
      mode: env.STORAGE_MODE || 'local',
      localDir: env.STORAGE_LOCAL_DIR || 'storage',
    },
  };
}

module.exports = { load, REQUIRED };
