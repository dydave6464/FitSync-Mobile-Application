'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const AppError = require('../src/lib/app-error');

test('carries status, code, message and details', () => {
  const err = new AppError(422, 'BAD_THING', 'It broke', [{ field: 'email' }]);
  assert.equal(err.status, 422);
  assert.equal(err.code, 'BAD_THING');
  assert.equal(err.message, 'It broke');
  assert.deepEqual(err.details, [{ field: 'email' }]);
});

test('is a real Error', () => {
  const err = new AppError(400, 'X', 'y');
  assert.ok(err instanceof Error);
  assert.ok(err instanceof AppError);
  assert.ok(err.stack);
});

test('details defaults to an empty array', () => {
  assert.deepEqual(new AppError(400, 'X', 'y').details, []);
});

test('static helpers set the right status', () => {
  assert.equal(AppError.badRequest('A', 'm').status, 400);
  assert.equal(AppError.unauthorized('A', 'm').status, 401);
  assert.equal(AppError.forbidden('A', 'm').status, 403);
  assert.equal(AppError.notFound('A', 'm').status, 404);
  assert.equal(AppError.conflict('A', 'm').status, 409);
});
