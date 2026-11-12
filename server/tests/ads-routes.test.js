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
const { manilaDay } = require('../src/lib/manila-day');

const storage = { url: (key) => `/storage/${key}` };

test('trainee ads', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool, storage });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const trainee = async ({ granted = false, paid = false } = {}) => {
    seq += 1;
    const [r] = await pool.query(
      'INSERT INTO users (email, password_hash, full_name, is_premium) VALUES (?, \'x\', ?, ?)',
      [`ads${seq}@example.com`, `Trainee ${seq}`, granted ? 1 : 0],
    );
    if (paid) {
      await pool.query(
        `INSERT INTO subscriptions (user_id, plan, price_php, status, expires_at)
         VALUES (?, 'monthly', 249, 'active', NOW() + INTERVAL 30 DAY)`, [r.insertId],
      );
    }
    return { userId: r.insertId, auth: { Authorization: `Bearer ${signToken(r.insertId, TEST_JWT)}` } };
  };
  const { adminId } = await createTestAdmin(pool);
  // An ad straight into the table; running unless told otherwise.
  const ad = async ({
    title = 'Promo', active = true, startsOn = manilaDay(1), endsOn = manilaDay(-1), linkUrl = 'https://example.com',
  } = {}) => {
    const [r] = await pool.query(
      `INSERT INTO advertisements (title, image_url, link_url, advertiser, amount_php, starts_on, ends_on, is_active, added_by)
       VALUES (?, ?, ?, 'Advertiser', 500, ?, ?, ?, ?)`,
      [title, `ads/${title}.jpg`, linkUrl, startsOn, endsOn, active, adminId],
    );
    return r.insertId;
  };
  const counts = async (id) => {
    const [[row]] = await pool.query('SELECT views, taps FROM advertisements WHERE ad_id = ?', [id]);
    return [row.views, row.taps];
  };
  const current = async (u) => (await request(app).get('/api/v1/ads/current').set(u.auth).expect(200)).body.data;

  const free = await trainee();
  const granted = await trainee({ granted: true });
  const paid = await trainee({ paid: true });

  await t.test('no ads at all: ad is null', async () => {
    assert.deepEqual(await current(free), { ad: null });
  });

  await t.test('a free trainee gets the running ad, with only id, title, imageUrl and linkUrl', async () => {
    const id = await ad({ title: 'Running' });
    assert.deepEqual(await current(free), {
      ad: { id, title: 'Running', imageUrl: '/storage/ads/Running.jpg', linkUrl: 'https://example.com' },
    });
    await pool.query('DELETE FROM advertisements');
    const noLink = await ad({ title: 'NoLink', linkUrl: null });
    assert.deepEqual((await current(free)).ad, { id: noLink, title: 'NoLink', imageUrl: '/storage/ads/NoLink.jpg', linkUrl: null });
  });

  await t.test('Pro, granted or paid, gets no ad', async () => {
    assert.deepEqual(await current(granted), { ad: null });
    assert.deepEqual(await current(paid), { ad: null });
  });

  await t.test('paused, scheduled and ended ads are never served', async () => {
    await pool.query('DELETE FROM advertisements');
    await ad({ title: 'Paused', active: false });
    await ad({ title: 'Scheduled', startsOn: manilaDay(-1), endsOn: manilaDay(-5) });
    await ad({ title: 'Ended', startsOn: manilaDay(5), endsOn: manilaDay(1) });
    assert.deepEqual(await current(free), { ad: null });
    // The run's first and last days are run days.
    const oneDay = await ad({ title: 'Today', startsOn: manilaDay(), endsOn: manilaDay() });
    assert.equal((await current(free)).ad.id, oneDay);
  });

  await t.test('with two running ads, each is picked some of the time', async () => {
    await pool.query('DELETE FROM advertisements');
    const a = await ad({ title: 'A' });
    const b = await ad({ title: 'B' });
    const seen = new Set();
    for (let i = 0; i < 40 && seen.size < 2; i += 1) seen.add((await current(free)).ad.id);
    assert.deepEqual([...seen].sort((x, y) => x - y), [a, b]);
  });

  await t.test('a view and a tap are 204 and counted for a free trainee on a running ad', async () => {
    await pool.query('DELETE FROM advertisements');
    const id = await ad();
    await request(app).post(`/api/v1/ads/${id}/view`).set(free.auth).expect(204);
    await request(app).post(`/api/v1/ads/${id}/view`).set(free.auth).expect(204);
    await request(app).post(`/api/v1/ads/${id}/tap`).set(free.auth).expect(204);
    assert.deepEqual(await counts(id), [2, 1]);
  });

  await t.test('Pro, a not-running ad or an unknown id: still 204, nothing counted', async () => {
    await pool.query('DELETE FROM advertisements');
    const running = await ad();
    const paused = await ad({ title: 'Paused', active: false });
    const scheduled = await ad({ title: 'Scheduled', startsOn: manilaDay(-1), endsOn: manilaDay(-5) });
    const ended = await ad({ title: 'Ended', startsOn: manilaDay(5), endsOn: manilaDay(1) });
    for (const kind of ['view', 'tap']) {
      await request(app).post(`/api/v1/ads/${running}/${kind}`).set(granted.auth).expect(204);
      await request(app).post(`/api/v1/ads/${running}/${kind}`).set(paid.auth).expect(204);
      for (const id of [paused, scheduled, ended]) {
        await request(app).post(`/api/v1/ads/${id}/${kind}`).set(free.auth).expect(204);
      }
      for (const id of ['999999', 'abc', '0']) {
        await request(app).post(`/api/v1/ads/${id}/${kind}`).set(free.auth).expect(204);
      }
    }
    for (const id of [running, paused, scheduled, ended]) assert.deepEqual(await counts(id), [0, 0]);
  });

  await t.test('no token is 401', async () => {
    const id = await ad();
    // Built one at a time: supertest starts a server per request object.
    for (const send of [
      () => request(app).get('/api/v1/ads/current'),
      () => request(app).post(`/api/v1/ads/${id}/view`),
      () => request(app).post(`/api/v1/ads/${id}/tap`),
    ]) {
      const res = await send().expect(401);
      assert.equal(res.body.error.code, 'UNAUTHENTICATED');
    }
    assert.deepEqual(await counts(id), [0, 0]);
  });

  await t.test('an admin token is 401', async () => {
    const { auth } = await createTestAdmin(pool, { email: 'other-admin@fitsync.test' });
    const res = await request(app).get('/api/v1/ads/current').set(auth).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('a suspended trainee is 403 ACCOUNT_SUSPENDED', async () => {
    const u = await trainee();
    await pool.query('UPDATE users SET suspended_at = NOW() WHERE user_id = ?', [u.userId]);
    const id = await ad();
    for (const send of [
      () => request(app).get('/api/v1/ads/current'),
      () => request(app).post(`/api/v1/ads/${id}/view`),
    ]) {
      const res = await send().set(u.auth).expect(403);
      assert.equal(res.body.error.code, 'ACCOUNT_SUSPENDED');
    }
    assert.deepEqual(await counts(id), [0, 0]);
  });
});
