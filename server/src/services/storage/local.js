'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

function create(rootDir) {
  const root = path.resolve(rootDir);

  function resolveKey(key) {
    if (key === '' || key === '.') {
      throw new Error(`Invalid storage key: ${key}`);
    }
    const full = path.resolve(root, key);
    if (full !== root && !full.startsWith(root + path.sep)) {
      throw new Error(`Invalid storage key: ${key}`);
    }
    return full;
  }

  return {
    // Storage interface: put(key, buffer, contentType). contentType is part
    // of the boundary so an object-storage driver (S3, GCS) can set it at
    // upload time without callers changing — those backends serve objects
    // as application/octet-stream otherwise. The local disk driver has no
    // place to store a MIME type, so it accepts and ignores the argument.
    // Written to a temp path and renamed into place rather than written
    // straight to `full`: rename within one directory is atomic, so any
    // consumer that sees exists(key) === true is guaranteed a complete file,
    // never a partial one left by a crash or an ENOSPC mid-write. The temp
    // path is derived from `full` (already validated by resolveKey), never
    // from the raw key, so it inherits the same traversal guard.
    async put(key, buffer, _contentType) {
      const full = resolveKey(key);
      await fs.mkdir(path.dirname(full), { recursive: true });
      const tempPath = `${full}.tmp-${crypto.randomUUID()}`;
      try {
        await fs.writeFile(tempPath, buffer);
        await fs.rename(tempPath, full);
      } catch (err) {
        await fs.rm(tempPath, { force: true });
        throw err;
      }
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
