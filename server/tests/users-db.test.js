'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  findUserByEmail, findUserById, createUserWithPassword, findOrCreateGoogleUser,
} = require('../src/db/users');

test('user queries', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const reset = async () => {
    await pool.query('DELETE FROM user_identities');
    await pool.query('DELETE FROM users');
  };

  await t.test('creates and finds a password user', async () => {
    await reset();
    const created = await createUserWithPassword(pool, {
      email: 'juan@example.com', passwordHash: 'hashed', fullName: 'Juan Dela Cruz',
    });
    assert.ok(created.user_id);
    const found = await findUserByEmail(pool, 'juan@example.com');
    assert.equal(found.full_name, 'Juan Dela Cruz');
    assert.equal((await findUserById(pool, created.user_id)).email, 'juan@example.com');
  });

  await t.test('email lookup is case-insensitive', async () => {
    await reset();
    await createUserWithPassword(pool, {
      email: 'juan@example.com', passwordHash: 'hashed', fullName: 'Juan',
    });
    assert.ok(await findUserByEmail(pool, 'JUAN@Example.COM'));
  });

  await t.test('creates a Google user with no password', async () => {
    await reset();
    const { user, isNew } = await findOrCreateGoogleUser(pool, {
      subject: 'sub-1', email: 'maria@example.com', emailVerified: true, fullName: 'Maria',
    });
    assert.equal(isNew, true);
    assert.equal(user.password_hash, null);
    const [ids] = await pool.query('SELECT * FROM user_identities');
    assert.equal(ids.length, 1);
    assert.equal(ids[0].provider_subject, 'sub-1');
  });

  await t.test('returns the same user on a second sign-in', async () => {
    await reset();
    const first = await findOrCreateGoogleUser(pool, {
      subject: 'sub-1', email: 'maria@example.com', emailVerified: true, fullName: 'Maria',
    });
    const second = await findOrCreateGoogleUser(pool, {
      subject: 'sub-1', email: 'maria@example.com', emailVerified: true, fullName: 'Maria',
    });
    assert.equal(second.isNew, false);
    assert.equal(second.user.user_id, first.user.user_id);
  });

  await t.test('matches on subject even after the email changes', async () => {
    await reset();
    const first = await findOrCreateGoogleUser(pool, {
      subject: 'sub-1', email: 'old@example.com', emailVerified: true, fullName: 'Maria',
    });
    const again = await findOrCreateGoogleUser(pool, {
      subject: 'sub-1', email: 'new@example.com', emailVerified: true, fullName: 'Maria',
    });
    assert.equal(again.user.user_id, first.user.user_id, 'sub is the identity, not email');
  });

  await t.test('links a verified Google identity to an existing password account', async () => {
    await reset();
    const existing = await createUserWithPassword(pool, {
      email: 'juan@example.com', passwordHash: 'hashed', fullName: 'Juan',
    });
    const { user, isNew } = await findOrCreateGoogleUser(pool, {
      subject: 'sub-juan', email: 'juan@example.com', emailVerified: true, fullName: 'Juan',
    });
    assert.equal(isNew, false);
    assert.equal(user.user_id, existing.user_id, 'one person, one account');
    assert.ok(user.password_hash, 'linking must not wipe the password');
  });

  await t.test('refuses to link an unverified Google email', async () => {
    await reset();
    await createUserWithPassword(pool, {
      email: 'juan@example.com', passwordHash: 'hashed', fullName: 'Juan',
    });
    // Without this refusal, anyone who creates a Google account on someone
    // else's address takes over their FitSync account.
    await assert.rejects(
      () => findOrCreateGoogleUser(pool, {
        subject: 'attacker', email: 'juan@example.com', emailVerified: false, fullName: 'Not Juan',
      }),
      (err) => err.code === 'INVALID_GOOGLE_TOKEN',
    );
  });
});
