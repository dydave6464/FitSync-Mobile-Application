'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');

test('profile endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());
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
    auth = `Bearer ${res.body.data.token}`;
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
});
