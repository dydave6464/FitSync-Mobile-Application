'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Writable } = require('node:stream');
const errorHandler = require('../src/middleware/error-handler');
const { createLogger } = require('../src/lib/logger');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createUserWithPassword } = require('../src/db/users');
const { hashPassword } = require('../src/lib/passwords');

function captureLogger() {
  let output = '';
  const destination = new Writable({
    write(chunk, _encoding, callback) {
      output += chunk.toString();
      callback();
    },
  });
  // production env avoids the pino-pretty transport, which runs on a worker
  // thread and would bypass this synchronous capture stream.
  const logger = createLogger({ level: 'info', env: 'production', destination });
  return { logger, output: () => output };
}

function fakeReqRes() {
  const req = { id: 'test-request-id' };
  const res = {
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
  return { req, res };
}

test('error handler mysql2 sanitisation', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test(
    'a genuine failed INSERT never puts the bcrypt hash in the log output',
    async () => {
      await pool.query('DELETE FROM users');

      // A distinctive hash so a substring match below cannot be a false
      // positive against unrelated log content.
      const hash = await hashPassword('a-password-nobody-else-uses-in-this-test-suite');
      assert.match(hash, /^\$2[aby]\$/, 'sanity check: this really is a bcrypt hash');

      await createUserWithPassword(pool, {
        email: 'race@example.com', passwordHash: hash, fullName: 'First',
      });

      // Calling the db layer directly (rather than the HTTP route) reproduces
      // exactly the race the route's own findUserByEmail pre-check is meant
      // to close: two inserts for the same email, the second hitting the
      // table's real UNIQUE constraint at the database rather than being
      // caught in application code first.
      let caught = null;
      try {
        await createUserWithPassword(pool, {
          email: 'race@example.com', passwordHash: hash, fullName: 'Second',
        });
      } catch (err) {
        caught = err;
      }

      assert.ok(caught, 'expected the duplicate insert to fail');
      assert.equal(caught.code, 'ER_DUP_ENTRY');
      // Confirms the precondition this test exists to guard against: mysql2
      // really does attach the fully-interpolated SQL, hash included, to the
      // error it throws.
      assert.ok(caught.sql && caught.sql.includes(hash), 'sanity check: err.sql carries the hash');

      const { logger, output } = captureLogger();
      const { req, res } = fakeReqRes();
      errorHandler(logger)(caught, req, res, () => {});

      assert.doesNotMatch(output(), new RegExp(hash.replace(/[$.*+?^${}()|[\]\\]/g, '\\$&')),
        'the bcrypt hash must never reach the log output');
    },
  );
});

test('a non-AppError 403 is not mislabelled as an unparseable body', () => {
  const { logger, output } = captureLogger();
  const { req, res } = fakeReqRes();

  // Shaped like the error express.static's dotfiles: 'deny' (or a
  // path-traversal attempt) raises: a bodyless GET, no AppError, status 403.
  const err = new Error('Forbidden');
  err.status = 403;

  errorHandler(logger)(err, req, res, () => {});

  assert.equal(res.statusCode, 403);
  assert.notEqual(res.body.error.code, 'INVALID_REQUEST_BODY');
  assert.doesNotMatch(res.body.error.message, /request body/i);
  assert.match(output(), /"code":"FORBIDDEN"/);
});

test('a non-AppError 404 is not mislabelled as an unparseable body', () => {
  const { logger } = captureLogger();
  const { req, res } = fakeReqRes();

  const err = new Error('Not Found');
  err.statusCode = 404;

  errorHandler(logger)(err, req, res, () => {});

  assert.equal(res.statusCode, 404);
  assert.notEqual(res.body.error.code, 'INVALID_REQUEST_BODY');
  assert.doesNotMatch(res.body.error.message, /request body/i);
});

test('a genuine body-parse 400 keeps its existing INVALID_REQUEST_BODY behaviour', () => {
  const { logger } = captureLogger();
  const { req, res } = fakeReqRes();

  const err = new Error('Unexpected token');
  err.status = 400;
  err.type = 'entity.parse.failed';

  errorHandler(logger)(err, req, res, () => {});

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error.code, 'INVALID_REQUEST_BODY');
});

test('error handler sanitisation of a mysql2-shaped error object', () => {
  const { logger, output } = captureLogger();
  const { req, res } = fakeReqRes();

  // Hand-built rather than a real driver error, so this test does not depend
  // on a live database: it pins the sanitisation behaviour itself.
  const err = new Error('ER_DUP_ENTRY: Duplicate entry');
  err.sql = "INSERT INTO users (email, password_hash) VALUES ('x@example.com', '$2b$10$totallyFakeHashValueThatMustNeverBeLogged')";
  err.sqlMessage = "Duplicate entry 'x@example.com' for key 'uq_users_email'";
  err.code = 'ER_DUP_ENTRY';
  err.errno = 1062;
  err.sqlState = '23000';

  errorHandler(logger)(err, req, res, () => {});

  const logged = output();
  assert.doesNotMatch(logged, /totallyFakeHashValueThatMustNeverBeLogged/, 'err.sql must not be logged verbatim');
  assert.doesNotMatch(logged, /x@example\.com/, 'err.sqlMessage must not be logged verbatim either');
  // The diagnostic value that is safe to keep must survive.
  assert.match(logged, /ER_DUP_ENTRY/);
  assert.match(logged, /1062/);
  assert.match(logged, /23000/);
});
