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

  const mailMode = env.MAIL_MODE || 'stub';
  // Verification is a hard gate: an unverified account cannot sign in. Stub
  // mail in production therefore does not degrade the product, it stops
  // registration entirely -- nobody would ever receive a link. Same reasoning
  // as the GOOGLE_MODE guard above: fail at startup, not in an incident.
  if (nodeEnv === 'production' && mailMode === 'stub') {
    throw new Error(
      'MAIL_MODE is "stub" (or unset) while NODE_ENV is "production". '
        + 'Verification email would never be sent and no user could register '
        + '— set MAIL_MODE=smtp.',
    );
  }

  const publicBaseUrl = env.PUBLIC_BASE_URL || 'http://localhost:3000';
  // Every emailed verification and password-reset link is built from this.
  // Left unset (or still pointing at localhost) it boots without error,
  // sends real mail, and every link in it points at a phone's own loopback
  // address -- every new registration and password reset is silently locked
  // out, with nothing in the response or the logs to say why. Same reasoning
  // as the two guards above: fail at startup, not in an incident.
  if (nodeEnv === 'production' && /^https?:\/\/(localhost|127(?:\.\d{1,3}){3})(?::\d+)?(?:\/|$)/i.test(publicBaseUrl)) {
    throw new Error(
      'PUBLIC_BASE_URL is unset or still points at localhost while NODE_ENV is '
        + '"production". Emailed links would be unreachable and every new '
        + 'registration or password reset would be silently locked out — set '
        + 'PUBLIC_BASE_URL to the public origin.',
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
    mail: {
      mode: mailMode,
      smtp: {
        host: env.SMTP_HOST || null,
        port: env.SMTP_PORT ? parsePositiveInteger('SMTP_PORT', env.SMTP_PORT) : null,
        user: env.SMTP_USER || null,
        password: env.SMTP_PASSWORD || null,
        from: env.MAIL_FROM || null,
      },
    },
    // Absolute base for links that arrive by email. localhost is right for a
    // desktop browser and wrong for a phone; see TODO-dave.md.
    publicBaseUrl,
  };
}

module.exports = { load, REQUIRED };
