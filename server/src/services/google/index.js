'use strict';
const stub = require('./stub');
const httpClient = require('./http-client');

function createGoogleVerifier(googleConfig = {}) {
  const mode = googleConfig.mode || 'stub';

  if (mode === 'stub') return stub;

  if (mode === 'http') {
    if (!googleConfig.clientId) {
      throw new Error('GOOGLE_CLIENT_ID is required when GOOGLE_MODE=http');
    }
    return httpClient.create(googleConfig.clientId);
  }

  throw new Error(`Unsupported GOOGLE_MODE: ${mode}`);
}

module.exports = { createGoogleVerifier };
