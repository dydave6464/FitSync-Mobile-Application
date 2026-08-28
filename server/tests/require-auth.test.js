'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { signToken } = require('../src/lib/tokens');

test('requireAuth', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const cases = [
    ['no header at all', null],
    ['a bare token with no scheme', 'abc.def.ghi'],
    ['the wrong scheme', 'Basic abc'],
    ['a token signed with another secret', `Bearer ${signToken(1, { secret: 'other-secret-value', expiresIn: '1h' })}`],
  ];

  for (const [label, header] of cases) {
    await t.test(`rejects ${label}`, async () => {
      const req = request(app).get('/api/v1/auth/me');
      if (header) req.set('Authorization', header);
      const res = await req.expect(401);
      assert.equal(res.body.error.code, 'UNAUTHENTICATED');
    });
  }

  await t.test('rejects a token whose user no longer exists', async () => {
    const res = await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${signToken(999999, { secret: 'test-secret-value-at-least-32-chars', expiresIn: '1h' })}`)
      .expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('the exercise catalogue now requires a token', async () => {
    const res = await request(app).get('/api/v1/exercises').expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });
});
