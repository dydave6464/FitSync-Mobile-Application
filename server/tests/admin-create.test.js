'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { verifyPassword } = require('../src/lib/passwords');
const { createAdminAccount, findAdminByEmail, findAdminById } = require('../src/db/admins');
const { parseArgs } = require('../scripts/admin-create');

test('admin:create reads --email and --name', () => {
  assert.deepEqual(parseArgs(['--email', 'A@X.test', '--name', 'Ada']), { email: 'a@x.test', fullName: 'Ada' });
  assert.deepEqual(parseArgs(['--name', 'Ada Lovelace', '--email', ' a@x.test ']), { email: 'a@x.test', fullName: 'Ada Lovelace' });
  assert.equal(parseArgs([]), null);
  assert.equal(parseArgs(['--email', 'a@x.test']), null);
  assert.equal(parseArgs(['--name', 'Ada']), null);
  assert.equal(parseArgs(['--email', 'a@x.test', '--name']), null);
});

test('createAdminAccount', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const refuses = (fields, code) => assert.rejects(
    () => createAdminAccount(pool, { email: 'new@x.test', fullName: 'New', password: 'admin-pass-123', ...fields }),
    (err) => err instanceof Error && err.code === code,
    code,
  );

  await t.test('creates an admin whose password verifies, email stored lower-case', async () => {
    const { adminId } = await createAdminAccount(pool, {
      email: 'Ada@FitSync.Test', fullName: 'Ada Admin', password: 'admin-pass-123',
    });
    assert.ok(Number.isInteger(adminId) && adminId > 0);
    const row = await findAdminById(pool, adminId);
    assert.equal(row.email, 'ada@fitsync.test');
    assert.equal(row.full_name, 'Ada Admin');
    assert.equal(await verifyPassword('admin-pass-123', row.password_hash), true);
    assert.notEqual(row.password_hash, 'admin-pass-123');
    assert.deepEqual(Object.keys(row).sort(), ['admin_id', 'created_at', 'email', 'full_name', 'password_hash']);
  });

  await t.test('finds an admin by email in any case, and by id', async () => {
    const row = await findAdminByEmail(pool, 'ADA@fitsync.TEST');
    assert.equal(row.email, 'ada@fitsync.test');
    assert.equal((await findAdminById(pool, row.admin_id)).email, 'ada@fitsync.test');
    assert.equal(await findAdminByEmail(pool, 'nobody@fitsync.test'), null);
    assert.equal(await findAdminById(pool, 999999), null);
  });

  await t.test('refuses a password shorter than 8 or longer than 72', async () => {
    await refuses({ password: 'a'.repeat(7) }, 'PASSWORD_TOO_SHORT');
    await refuses({ password: 'a'.repeat(73) }, 'PASSWORD_TOO_LONG');
  });

  await t.test('refuses an email an admin already has', async () => {
    await refuses({ email: 'ADA@fitsync.test' }, 'EMAIL_IN_USE');
  });

  await t.test('refuses an email a trainee already has, in any case', async () => {
    await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('juan@example.com', 'x', 'Juan')");
    await refuses({ email: 'Juan@Example.com' }, 'EMAIL_IN_USE');
  });

  await t.test('refuses an empty name and a malformed email', async () => {
    await refuses({ fullName: '   ' }, 'INVALID_NAME');
    await refuses({ email: 'not-an-email' }, 'INVALID_EMAIL');
  });

  await t.test('a refused account leaves no row behind', async () => {
    const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM admins');
    assert.equal(Number(n), 1);
  });
});
