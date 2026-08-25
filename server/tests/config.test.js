'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, REQUIRED } = require('../src/config');

const validEnv = {
  DB_HOST: '127.0.0.1',
  DB_PORT: '3306',
  DB_USER: 'fitsync',
  DB_PASSWORD: 'secret',
  DB_NAME: 'fitsync',
};

test('load throws listing every missing required key', () => {
  assert.throws(
    () => load({ DB_HOST: '127.0.0.1' }),
    (err) => {
      assert.match(err.message, /DB_PORT/);
      assert.match(err.message, /DB_USER/);
      assert.match(err.message, /DB_PASSWORD/);
      assert.match(err.message, /DB_NAME/);
      return true;
    },
  );
});

test('load applies documented defaults', () => {
  const cfg = load(validEnv);
  assert.equal(cfg.env, 'development');
  assert.equal(cfg.port, 3000);
  assert.equal(cfg.logLevel, 'info');
  assert.equal(cfg.ml.mode, 'stub');
  assert.equal(cfg.storage.mode, 'local');
  assert.equal(cfg.db.connectionLimit, 10);
});

test('load coerces numeric env values to numbers', () => {
  const cfg = load({ ...validEnv, PORT: '8080', DB_PORT: '3307' });
  assert.equal(cfg.port, 8080);
  assert.equal(cfg.db.port, 3307);
  assert.equal(typeof cfg.port, 'number');
});

test('REQUIRED lists exactly the five database keys', () => {
  assert.deepEqual(REQUIRED, ['DB_HOST', 'DB_PORT', 'DB_USER', 'DB_PASSWORD', 'DB_NAME']);
});
