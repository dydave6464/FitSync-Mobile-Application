'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { seedEquipment } = require('../src/db/seed-equipment');
const { markEmailVerified } = require('../src/db/users');

test('profile endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());
  await seedEquipment(testDbConfig());
  const app = buildTestApp({ pool });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  let auth;
  const reset = async () => {
    await pool.query('DELETE FROM user_injuries');
    await pool.query('DELETE FROM user_equipment');
    await pool.query('DELETE FROM user_identities');
    await pool.query('DELETE FROM users');
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email: 'p@example.com', password: 's3cret-pass', fullName: 'P' }).expect(201);
    // These tests exercise profile endpoints behind requireAuth, not the
    // verification gate itself (that belongs to auth-verification.test.js),
    // so verify the throwaway account directly rather than routing it
    // through the mail flow. Registration alone no longer grants a session,
    // so sign in afterward for a real token.
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'p@example.com', password: 's3cret-pass' }).expect(200);
    auth = `Bearer ${login.body.data.token}`;
  };

  await t.test('requires a token', async () => {
    await reset();
    const res = await request(app).get('/api/v1/profile').expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('returns the profile with empty selections', async () => {
    await reset();
    const res = await request(app).get('/api/v1/profile').set('Authorization', auth).expect(200);
    assert.equal(res.body.data.profile.mainGoal, null);
    assert.deepEqual(res.body.data.profile.equipment, []);
    assert.equal(res.body.data.profile.onboardingCompleted, false);
  });

  // getProfile's explicit SELECT list (rather than SELECT *) is what keeps
  // this safe today; nothing pinned that until now.
  await t.test('never returns password_hash on the profile', async () => {
    await reset();
    const res = await request(app).get('/api/v1/profile').set('Authorization', auth).expect(200);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(res.body.data.profile, 'password_hash'),
      'password_hash must never reach the client',
    );
    assert.ok(
      !Object.prototype.hasOwnProperty.call(res.body.data.profile, 'passwordHash'),
      'passwordHash must never reach the client either',
    );
  });

  await t.test('patches one step at a time', async () => {
    await reset();
    await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ mainGoal: 'improve_endurance' }).expect(200);
    const res = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ fitnessLevel: 'intermediate' }).expect(200);
    assert.equal(res.body.data.profile.mainGoal, 'improve_endurance');
    assert.equal(res.body.data.profile.fitnessLevel, 'intermediate');
  });

  await t.test('rejects a value outside the enum', async () => {
    await reset();
    const res = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ mainGoal: 'gain_strength' }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  await t.test('refuses to write a field that is not editable', async () => {
    await reset();
    await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ isPremium: true }).expect(200);
    const res = await request(app).get('/api/v1/profile').set('Authorization', auth).expect(200);
    assert.equal(res.body.data.profile.isPremium, false, 'isPremium is not writable here');
  });

  await t.test('lists injuries with laterality', async () => {
    await reset();
    const res = await request(app).get('/api/v1/injuries').set('Authorization', auth).expect(200);
    assert.equal(res.body.data.injuries.length, 16);
    assert.equal(res.body.data.injuries.find((i) => i.name === 'Neck').isLateral, false);
  });

  await t.test('replaces the injury set', async () => {
    await reset();
    const list = await request(app).get('/api/v1/injuries').set('Authorization', auth).expect(200);
    const knee = list.body.data.injuries.find((i) => i.name === 'Knee');
    const res = await request(app).put('/api/v1/profile/injuries').set('Authorization', auth)
      .send({ injuries: [{ injuryId: knee.injuryId, side: 'right' }] }).expect(200);
    assert.equal(res.body.data.profile.injuries[0].side, 'right');
  });

  await t.test('rejects an unknown side', async () => {
    await reset();
    const list = await request(app).get('/api/v1/injuries').set('Authorization', auth).expect(200);
    const knee = list.body.data.injuries.find((i) => i.name === 'Knee');
    const res = await request(app).put('/api/v1/profile/injuries').set('Authorization', auth)
      .send({ injuries: [{ injuryId: knee.injuryId, side: 'sideways' }] }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  await t.test('rejects null for a field that cannot be null', async () => {
    await reset();
    const res = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ fullName: null }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');

    const res2 = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ notificationsEnabled: null }).expect(400);
    assert.equal(res2.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  await t.test('rejects a value longer than the column allows', async () => {
    await reset();
    const res = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ fullName: 'a'.repeat(256) }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');

    const res2 = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ city: 'a'.repeat(256) }).expect(400);
    assert.equal(res2.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  // The max-length guard used to read `typeof value === 'string' && ...`,
  // which means a non-string value skipped that check AND every other type
  // check, and reached pool.query as-is: an array becomes a SQL syntax error
  // (500) and an object stores the literal text "[object Object]".
  await t.test('rejects a non-string value for a string field instead of reaching SQL', async () => {
    await reset();
    const arrayRes = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ fullName: ['a', 'b'] }).expect(400);
    assert.equal(arrayRes.body.error.code, 'INVALID_PROFILE_FIELD');

    const objectRes = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ city: { nested: true } }).expect(400);
    assert.equal(objectRes.body.error.code, 'INVALID_PROFILE_FIELD');

    const numberRes = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ city: 12345 }).expect(400);
    assert.equal(numberRes.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  // The old regex /^\d{4}-\d{2}-\d{2}$/ only checks shape, so "2026-02-31"
  // passes it and reaches MySQL, which rejects it under STRICT_TRANS_TABLES
  // as a 500 — a 400 belongs here instead.
  await t.test('rejects a date of birth that is not a real calendar date', async () => {
    await reset();
    const res = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ dateOfBirth: '2026-02-31' }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');

    const res2 = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ dateOfBirth: '2026-13-01' }).expect(400);
    assert.equal(res2.body.error.code, 'INVALID_PROFILE_FIELD');

    // 2026 is not a leap year.
    const res3 = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ dateOfBirth: '2026-02-29' }).expect(400);
    assert.equal(res3.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  await t.test('accepts a real calendar date, including a leap day', async () => {
    await reset();
    const res = await request(app).patch('/api/v1/profile').set('Authorization', auth)
      .send({ dateOfBirth: '2024-02-29' }).expect(200);
    assert.equal(res.body.data.profile.dateOfBirth.slice(0, 10), '2024-02-29');
  });

  await t.test('rejects a side on a non-lateral injury and stores nothing', async () => {
    await reset();
    const list = await request(app).get('/api/v1/injuries').set('Authorization', auth).expect(200);
    const neck = list.body.data.injuries.find((i) => i.name === 'Neck');
    const res = await request(app).put('/api/v1/profile/injuries').set('Authorization', auth)
      .send({ injuries: [{ injuryId: neck.injuryId, side: 'right' }] }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');

    const profile = await request(app).get('/api/v1/profile').set('Authorization', auth).expect(200);
    assert.deepEqual(profile.body.data.profile.injuries, [], 'the rejected entry must not be stored');
  });

  await t.test('rejects an equipment or injury id that does not exist', async () => {
    await reset();
    const badEquip = await request(app).put('/api/v1/profile/equipment').set('Authorization', auth)
      .send({ equipmentIds: [999999] }).expect(400);
    assert.equal(badEquip.body.error.code, 'INVALID_PROFILE_FIELD');

    const badInjury = await request(app).put('/api/v1/profile/injuries').set('Authorization', auth)
      .send({ injuries: [{ injuryId: 999999, side: null }] }).expect(400);
    assert.equal(badInjury.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  await t.test('rejects duplicate ids in an equipment or injury set', async () => {
    await reset();
    const dupEquip = await request(app).put('/api/v1/profile/equipment').set('Authorization', auth)
      .send({ equipmentIds: [1, 1] }).expect(400);
    assert.equal(dupEquip.body.error.code, 'INVALID_PROFILE_FIELD');

    const list = await request(app).get('/api/v1/injuries').set('Authorization', auth).expect(200);
    const knee = list.body.data.injuries.find((i) => i.name === 'Knee');
    const dupInjury = await request(app).put('/api/v1/profile/injuries').set('Authorization', auth)
      .send({
        injuries: [
          { injuryId: knee.injuryId, side: 'right' },
          { injuryId: knee.injuryId, side: 'left' },
        ],
      }).expect(400);
    assert.equal(dupInjury.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  await t.test('lists the eight curated chips in design order', async () => {
    await reset();
    // A raw, un-curated catalogue tag. is_user_selectable defaults to 0, so
    // this must never appear in the response — proves the endpoint excludes
    // raw catalogue tags, not just that it happens to have only 8 rows to
    // choose from (this file never runs the catalogue seed).
    await pool.query("INSERT IGNORE INTO equipment (name) VALUES ('yoga mat')");
    const res = await request(app).get('/api/v1/equipment')
      .set('Authorization', auth).expect(200);
    assert.deepEqual(res.body.data.equipment.map((e) => e.name), [
      'Barbell', 'Dumbbells', 'Bench', 'Pull-up bar',
      'Kettlebell', 'Bands', 'Machines', 'Bodyweight',
    ], 'the non-selectable "yoga mat" row must not be in this list');
  });

  // The subtest above cannot fail if `ORDER BY display_order` were removed:
  // seedEquipment inserts the eight rows in display order on a fresh table, so
  // insertion (id) order coincidentally satisfies that assertion too. Perturbing
  // one row's display_order and re-reading forces the ordering to come from the
  // column itself, not from insertion/id order.
  await t.test('orders strictly by display_order, not by insertion or id order', async () => {
    await reset();
    try {
      await pool.query("UPDATE equipment SET display_order = 99 WHERE display_name = 'Barbell'");
      const res = await request(app).get('/api/v1/equipment')
        .set('Authorization', auth).expect(200);
      assert.deepEqual(res.body.data.equipment.map((e) => e.name), [
        'Dumbbells', 'Bench', 'Pull-up bar', 'Kettlebell',
        'Bands', 'Machines', 'Bodyweight', 'Barbell',
      ], 'Barbell must sort last once its display_order is pushed past the rest, and the other seven must keep their relative order');
    } finally {
      // Re-seeding is idempotent (UPSERT_OPTION rewrites every option's
      // display_order from OPTIONS), so this restores Barbell to 1 even if the
      // assertion above throws — no later subtest inherits the perturbation.
      await seedEquipment(testDbConfig());
    }
  });

  await t.test('rejects a catalogue tag that is not user-selectable', async () => {
    await reset();
    // seedEquipment only INSERTs the eight curated names; it reaches 'cable'
    // through an UPDATE that no-ops when the row is absent. This file never
    // runs the catalogue seed, so the row has to be made here. A bare insert
    // lands is_user_selectable = 0 by column default, which is the condition
    // under test.
    await pool.query("INSERT IGNORE INTO equipment (name) VALUES ('cable')");
    const [[row]] = await pool.query(
      "SELECT equipment_id AS id FROM equipment WHERE name = 'cable'",
    );
    const res = await request(app).put('/api/v1/profile/equipment')
      .set('Authorization', auth).send({ equipmentIds: [row.id] }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_PROFILE_FIELD');
  });

  await t.test('returns the display name on the saved profile', async () => {
    await reset();
    const list = await request(app).get('/api/v1/equipment')
      .set('Authorization', auth).expect(200);
    const bodyweight = list.body.data.equipment.find((e) => e.name === 'Bodyweight');
    await request(app).put('/api/v1/profile/equipment')
      .set('Authorization', auth).send({ equipmentIds: [bodyweight.equipmentId] }).expect(200);
    const res = await request(app).get('/api/v1/profile')
      .set('Authorization', auth).expect(200);
    assert.deepEqual(res.body.data.profile.equipment.map((e) => e.name), ['Bodyweight'],
      'the profile must not show the raw catalogue name "body weight"');
  });

  await t.test('returns the account creation date as joinedAt', async () => {
    await reset();
    const res = await request(app).get('/api/v1/profile')
      .set('Authorization', auth).expect(200);
    const joinedAt = res.body.data.profile.joinedAt;
    assert.ok(joinedAt, 'joinedAt must be present');
    assert.match(joinedAt, /^\d{4}-\d{2}-\d{2}T/, 'an ISO-8601 UTC string');
    const age = Date.now() - Date.parse(joinedAt);
    assert.ok(age >= 0 && age < 60_000,
      'the account was just created, so joinedAt must be within the last minute');
  });

  // The freshness check above cannot fail if joinedAt were computed as
  // `new Date().toISOString()` at request time instead of read from the row:
  // a freshly-registered account's created_at is already "just now", so a
  // hardcoded current-time value would slip through unnoticed. Backdating
  // created_at to a fixed, known instant and asserting exact equality closes
  // that gap — only a real read of the stored row can reproduce this exact
  // timestamp; a call to Date.now() at request time would report today.
  await t.test('joinedAt reflects the stored creation date, not the current time', async () => {
    await reset();
    const knownDate = new Date('2020-06-15T12:00:00.000Z');
    // FROM_UNIXTIME(epoch) round-trips correctly regardless of the session's
    // time_zone: MySQL renders it as the epoch's wall-clock in session time,
    // then storing that into the TIMESTAMP column converts it back to the
    // same UTC instant, so this is not vulnerable to the bug joinedAt itself
    // had to be fixed for.
    await pool.query(
      'UPDATE users SET created_at = FROM_UNIXTIME(?) WHERE email = ?',
      [Math.floor(knownDate.getTime() / 1000), 'p@example.com'],
    );
    const res = await request(app).get('/api/v1/profile')
      .set('Authorization', auth).expect(200);
    assert.equal(res.body.data.profile.joinedAt, knownDate.toISOString(),
      'joinedAt must equal the row\'s created_at, not Date.now()');
  });
});
