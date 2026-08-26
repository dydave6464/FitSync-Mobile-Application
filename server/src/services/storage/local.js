'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');

function create(rootDir) {
  const root = path.resolve(rootDir);

  function resolveKey(key) {
    const full = path.resolve(root, key);
    if (full !== root && !full.startsWith(root + path.sep)) {
      throw new Error(`Invalid storage key: ${key}`);
    }
    return full;
  }

  return {
    async put(key, buffer) {
      const full = resolveKey(key);
      await fs.mkdir(path.dirname(full), { recursive: true });
      await fs.writeFile(full, buffer);
      return key;
    },

    async get(key) {
      return fs.readFile(resolveKey(key));
    },

    async delete(key) {
      await fs.rm(resolveKey(key), { force: true });
    },

    async exists(key) {
      try {
        await fs.access(resolveKey(key));
        return true;
      } catch {
        return false;
      }
    },

    url(key) {
      return `/storage/${key}`;
    },
  };
}

module.exports = { create };
