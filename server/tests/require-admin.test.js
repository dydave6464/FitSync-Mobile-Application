'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createTestAdmin, TEST_JWT } = require('./helpers/admin');
const { signToken } = require('../src/lib/tokens');
const { signAdminToken } = require('../src/lib/admin-tokens');

test('requireAdmin', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const unauthenticated = (res) => {
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
    assert.equal(res.body.error.message, 'Sign in again to continue.');
  };

  const admin = await createTestAdmin(pool);
  const [trainee] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name, email_verified) VALUES ('t@b.com', 'x', 'T', 1)",
  );

  await t.test('an admin token reaches GET /admin/me, which names the admin', async () => {
    const res = await request(app).get('/api/v1/admin/me').set(admin.auth).expect(200);
    assert.deepEqual(res.body, {
      data: { admin: { id: admin.adminId, email: 'admin@fitsync.test', fullName: 'Ada Admin' } },
    });
  });

  const refused = [
    ['no header at all', null],
    ['the wrong scheme', `Basic ${admin.token}`],
    ['a bare token', admin.token],
    ['a trainee token', `Bearer ${signToken(trainee.insertId, TEST_JWT, 0)}`],
    // admin_id 1 and user_id 1 are different people: a trainee token for the
    // same number is still a trainee token.
    ['a trainee token for the same number', `Bearer ${signToken(admin.adminId, TEST_JWT, 0)}`],
    ['an admin token signed with another secret',
      `Bearer ${signAdminToken(admin.adminId, { secret: 'another-secret-value-entirely', expiresIn: '1h' })}`],
  ];
  for (const [label, header] of refused) {
    await t.test(`refuses ${label} with 401`, async () => {
      const req = request(app).get('/api/v1/admin/me');
      if (header) req.set('Authorization', header);
      unauthenticated(await req.expect(401));
    });
  }

  await t.test('an admin token is refused on trainee routes', async () => {
    unauthenticated(await request(app).get('/api/v1/auth/me').set(admin.auth).expect(401));
    unauthenticated(await request(app).get('/api/v1/profile').set(admin.auth).expect(401));
  });

  await t.test("a deleted admin's token stops working", async () => {
    const gone = await createTestAdmin(pool, { email: 'gone@fitsync.test' });
    await request(app).get('/api/v1/admin/me').set(gone.auth).expect(200);
    await pool.query('DELETE FROM admins WHERE admin_id = ?', [gone.adminId]);
    unauthenticated(await request(app).get('/api/v1/admin/me').set(gone.auth).expect(401));
  });
});
