'use strict';
const stub = require('./stub');
const httpClient = require('./http-client');

/// Picks the FatSecret driver, like services/cues. Defaults to the stub so no
/// test makes a network call. No production guard, for the reason cues has
/// none: a stub degrades search to FitSync's own foods, which still works.
function createFatsecretService(cfg = {}, { fetchImpl, now } = {}) {
  const mode = cfg.mode || 'stub';
  if (mode === 'stub') return stub;
  if (mode === 'http') {
    if (!cfg.clientId) throw new Error('FATSECRET_CONSUMER_KEY is required when FATSECRET_MODE=http');
    if (!cfg.clientSecret) throw new Error('FATSECRET_CONSUMER_SECRET is required when FATSECRET_MODE=http');
    return httpClient.create({ clientId: cfg.clientId, clientSecret: cfg.clientSecret, fetchImpl, now });
  }
  throw new Error(`Unsupported FATSECRET_MODE: ${mode}`);
}

module.exports = { createFatsecretService };
