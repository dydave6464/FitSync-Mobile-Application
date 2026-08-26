'use strict';
const stub = require('./stub');
const httpClient = require('./http-client');

function createMlService(mlConfig = {}) {
  const mode = mlConfig.mode || 'stub';

  if (mode === 'stub') return stub;

  if (mode === 'http') {
    if (!mlConfig.serviceUrl) {
      throw new Error('ML_SERVICE_URL is required when ML_MODE=http');
    }
    return httpClient.create(mlConfig.serviceUrl);
  }

  throw new Error(`Unsupported ML_MODE: ${mode}`);
}

module.exports = { createMlService };
