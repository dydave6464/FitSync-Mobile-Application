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
  JWT_SECRET: 'x'.repeat(32),
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

test('REQUIRED lists exactly the database and auth keys', () => {
  assert.deepEqual(REQUIRED, ['DB_HOST', 'DB_PORT', 'DB_USER', 'DB_PASSWORD', 'DB_NAME', 'JWT_SECRET']);
});

test('load rejects a required key that is present but empty', () => {
  assert.throws(
    () => load({ ...validEnv, DB_PASSWORD: '' }),
    /DB_PASSWORD/,
  );
});

test('load rejects an unparseable PORT rather than binding a random port', () => {
  assert.throws(() => load({ ...validEnv, PORT: 'abc' }), /PORT/);
});

test('load rejects an unparseable DB_PORT', () => {
  assert.throws(() => load({ ...validEnv, DB_PORT: 'abc' }), /DB_PORT/);
});

test('load rejects a zero or negative PORT', () => {
  assert.throws(() => load({ ...validEnv, PORT: '0' }), /PORT/);
  assert.throws(() => load({ ...validEnv, PORT: '-1' }), /PORT/);
});

test('load rejects a non-integer PORT', () => {
  assert.throws(() => load({ ...validEnv, PORT: '3000.5' }), /PORT/);
});

test('requires JWT_SECRET', () => {
  const env = { ...validEnv };
  delete env.JWT_SECRET;
  assert.throws(() => load(env), /JWT_SECRET/);
});

test('rejects an empty JWT_SECRET rather than defaulting', () => {
  assert.throws(() => load({ ...validEnv, JWT_SECRET: '' }), /JWT_SECRET/);
});

test('exposes jwt and google config', () => {
  const cfg = load({ ...validEnv, JWT_SECRET: 'x'.repeat(32), GOOGLE_CLIENT_ID: 'cid' });
  assert.equal(cfg.jwt.secret, 'x'.repeat(32));
  assert.equal(cfg.jwt.expiresIn, '30d');
  assert.equal(cfg.google.mode, 'stub');
  assert.equal(cfg.google.clientId, 'cid');
});

test('refuses to start with GOOGLE_MODE=stub in production', () => {
  assert.throws(
    () => load({ ...validEnv, NODE_ENV: 'production', GOOGLE_MODE: 'stub' }),
    (err) => {
      assert.match(err.message, /GOOGLE_MODE/);
      assert.match(err.message, /NODE_ENV/);
      return true;
    },
  );
});

test('allows GOOGLE_MODE=stub outside production', () => {
  const cfg = load({ ...validEnv, NODE_ENV: 'development', GOOGLE_MODE: 'stub' });
  assert.equal(cfg.google.mode, 'stub');
});

test('allows GOOGLE_MODE=http in production', () => {
  const cfg = load({
    ...validEnv, NODE_ENV: 'production', GOOGLE_MODE: 'http', MAIL_MODE: 'smtp',
    PUBLIC_BASE_URL: 'https://fitsync.example.com',
  });
  assert.equal(cfg.google.mode, 'http');
});

test('defaulting GOOGLE_MODE (unset) is refused in production, same as an explicit stub', () => {
  const env = { ...validEnv, NODE_ENV: 'production' };
  delete env.GOOGLE_MODE;
  assert.throws(() => load(env), /GOOGLE_MODE/);
});

const prodEnv = { ...validEnv, NODE_ENV: 'production', GOOGLE_MODE: 'http', MAIL_MODE: 'smtp' };

test('refuses to start with PUBLIC_BASE_URL unset in production', () => {
  assert.throws(
    () => load({ ...prodEnv }),
    (err) => {
      assert.match(err.message, /PUBLIC_BASE_URL/);
      assert.match(err.message, /NODE_ENV/);
      return true;
    },
  );
});

test('refuses to start with PUBLIC_BASE_URL still pointing at localhost in production', () => {
  assert.throws(
    () => load({ ...prodEnv, PUBLIC_BASE_URL: 'http://localhost:3000' }),
    /PUBLIC_BASE_URL/,
  );
});

test('refuses to start with a PUBLIC_BASE_URL of 127.0.0.1 in production', () => {
  assert.throws(
    () => load({ ...prodEnv, PUBLIC_BASE_URL: 'http://127.0.0.1:3000' }),
    /PUBLIC_BASE_URL/,
  );
});

test('allows a real PUBLIC_BASE_URL in production', () => {
  const cfg = load({ ...prodEnv, PUBLIC_BASE_URL: 'https://fitsync.example.com' });
  assert.equal(cfg.publicBaseUrl, 'https://fitsync.example.com');
});

test('allows PUBLIC_BASE_URL to default to localhost outside production', () => {
  const cfg = load({ ...validEnv, NODE_ENV: 'development' });
  assert.equal(cfg.publicBaseUrl, 'http://localhost:3000');
});
