'use strict';
require('dotenv').config({ quiet: true });

const REQUIRED = ['DB_HOST', 'DB_PORT', 'DB_USER', 'DB_PASSWORD', 'DB_NAME', 'JWT_SECRET'];

function parsePositiveInteger(name, value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) {
    throw new Error(`${name} must be a positive integer, got: ${value}`);
  }
  return n;
}

function load(env = process.env) {
  const missing = REQUIRED.filter((key) => !env[key]);
  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }

  const nodeEnv = env.NODE_ENV || 'development';
  const googleMode = env.GOOGLE_MODE || 'stub';
  // The stub driver accepts a small, fixed set of tokens that are public in
  // this repository (see src/services/google/stub.js) — one of them signs in
  // as juan@example.com, creating the account if it does not exist yet.
  // Refusing to boot here mirrors the JWT_SECRET guard above: a predictable
  // auth bypass in production is exactly the kind of thing that must fail
  // fast at startup, not in an incident.
  if (nodeEnv === 'production' && googleMode === 'stub') {
    throw new Error(
      'GOOGLE_MODE is "stub" (or unset) while NODE_ENV is "production". '
        + 'The stub driver accepts publicly known tokens and must never run in '
        + 'production — set GOOGLE_MODE=http.',
    );
  }

  return {
    env: nodeEnv,
    port: env.PORT ? parsePositiveInteger('PORT', env.PORT) : 3000,
    logLevel: env.LOG_LEVEL || 'info',
    db: {
      host: env.DB_HOST,
      port: parsePositiveInteger('DB_PORT', env.DB_PORT),
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
    jwt: {
      secret: env.JWT_SECRET,
      // Long-lived on purpose: there are no refresh tokens, so expiry means
      // signing in again. See the spec, section 2.
      expiresIn: env.JWT_EXPIRES_IN || '30d',
    },
    google: {
      mode: googleMode,
      clientId: env.GOOGLE_CLIENT_ID || null,
    },
  };
}

module.exports = { load, REQUIRED };
