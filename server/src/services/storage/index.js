'use strict';
const local = require('./local');

function createStorage(storageConfig = {}) {
  const mode = storageConfig.mode || 'local';

  if (mode === 'local') {
    return local.create(storageConfig.localDir || 'storage');
  }

  throw new Error(`Unsupported STORAGE_MODE: ${mode}`);
}

module.exports = { createStorage };
