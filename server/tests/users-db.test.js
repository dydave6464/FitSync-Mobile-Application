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

  await t.test('refuses an unverified email when no account exists yet, and creates nothing', async () => {
    await reset();
    // Nobody has signed up with this address yet. Without a gate here, an
    // attacker's unverified token would create the account unconditionally,
    // pre-seeding it for the real owner to later "link" into on their behalf.
    await assert.rejects(
      () => findOrCreateGoogleUser(pool, {
        subject: 'attacker', email: 'victim@example.com', emailVerified: false, fullName: 'Not Victim',
      }),
      (err) => err.code === 'INVALID_GOOGLE_TOKEN',
    );
    const [users] = await pool.query('SELECT * FROM users');
    assert.equal(users.length, 0, 'no account should be created by an unverified sign-in');
    const [ids] = await pool.query('SELECT * FROM user_identities');
    assert.equal(ids.length, 0, 'no identity should be recorded either');
  });

  await t.test('a two-call pre-hijack attempt cannot plant an account for the victim to later link into', async () => {
    await reset();
    // Call 1: attacker, unverified, on the victim's address, before the
    // victim has ever signed up. Must be refused outright.
    await assert.rejects(
      () => findOrCreateGoogleUser(pool, {
        subject: 'attacker-sub', email: 'victim@example.com', emailVerified: false, fullName: 'Not Victim',
      }),
      (err) => err.code === 'INVALID_GOOGLE_TOKEN',
    );
    // Call 2: the real victim, genuinely verified, same address. This must
    // create a fresh account of their own, not link into anything the
    // attacker's call might have planted.
    const { user, isNew } = await findOrCreateGoogleUser(pool, {
      subject: 'victim-sub', email: 'victim@example.com', emailVerified: true, fullName: 'Victim',
    });
    assert.equal(isNew, true, 'the victim must get a brand-new account, not a hijacked one');
    const [users] = await pool.query('SELECT * FROM users');
    assert.equal(users.length, 1, 'only the victim\'s own account should exist');
    assert.equal(users[0].user_id, user.user_id);
  });

  await t.test('a returning user still works even if their token comes back unverified', async () => {
    await reset();
    const first = await findOrCreateGoogleUser(pool, {
      subject: 'sub-1', email: 'maria@example.com', emailVerified: true, fullName: 'Maria',
    });
    // Branch 1 matches on subject alone and never re-litigates verification;
    // gating above it would lock out a legitimate returning user.
    const second = await findOrCreateGoogleUser(pool, {
      subject: 'sub-1', email: 'maria@example.com', emailVerified: false, fullName: 'Maria',
    });
    assert.equal(second.isNew, false);
    assert.equal(second.user.user_id, first.user.user_id);
  });

  await t.test('refuses an identity with no email', async () => {
    await reset();
    await assert.rejects(
      () => findOrCreateGoogleUser(pool, {
        subject: 'sub-no-email', email: null, emailVerified: true, fullName: 'No Email',
      }),
      (err) => err.code === 'INVALID_GOOGLE_TOKEN',
    );
  });
});
