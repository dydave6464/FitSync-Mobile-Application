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
const { adStatus, listAdsForMonth } = require('../src/db/ads');

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d]);
const b64 = (buf) => buf.toString('base64');
const AD_KEYS = [
  'active', 'advertiser', 'amountPhp', 'endsOn', 'id', 'imageUrl', 'linkUrl', 'startsOn', 'status', 'taps', 'title',
  'views',
];
const KEY = /^ads\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png)$/;

/// The storage driver's interface, in memory, recording every call.
function memoryStorage() {
  const files = new Map();
  const calls = [];
  return {
    files,
    calls,
    async put(key, bytes, mimeType) { calls.push(['put', key, mimeType]); files.set(key, bytes); return key; },
    async delete(key) { calls.push(['delete', key]); files.delete(key); },
    url: (key) => `/storage/${key}`,
  };
}

test('admin ads endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const storage = memoryStorage();
  const app = buildTestApp({ pool, storage });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const { auth, adminId } = await createTestAdmin(pool);
  const get = (path) => request(app).get(`/api/v1/admin${path}`).set(auth);
  const post = (path, body) => request(app).post(`/api/v1/admin${path}`).set(auth).send(body);
  const patch = (path, body) => request(app).patch(`/api/v1/admin${path}`).set(auth).send(body);

  const today = manilaDay();
  const valid = (over = {}) => ({
    title: 'Protein bar promo',
    advertiser: 'Bar Co.',
    amountPhp: 1200.5,
    startsOn: manilaDay(1),
    endsOn: manilaDay(-29),
    linkUrl: 'https://example.com/bar',
    image: b64(JPEG),
    mimeType: 'image/jpeg',
    ...over,
  });
  const adRow = async (id) => {
    const [[row]] = await pool.query(
      `SELECT title, image_url, link_url, advertiser, amount_php, is_active, added_by,
              DATE_FORMAT(starts_on, '%Y-%m-%d') AS starts_on, DATE_FORMAT(ends_on, '%Y-%m-%d') AS ends_on
         FROM advertisements WHERE ad_id = ?`, [id],
    );
    return row;
  };
  const fieldOf = (res) => {
    assert.equal(res.status, 400, JSON.stringify(res.body));
    assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD');
    return res.body.error.details[0].field;
  };

  await t.test('a trainee token is refused', async () => {
    const [u] = await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('t@example.com', 'x', 'T')");
    const token = signToken(u.insertId, TEST_JWT);
    // Built one at a time: supertest starts a server per request object.
    for (const send of [
      () => request(app).get('/api/v1/admin/ads'),
      () => request(app).post('/api/v1/admin/ads').send(valid()),
      () => request(app).patch('/api/v1/admin/ads/1').send({ active: false }),
    ]) {
      const res = await send().set('Authorization', `Bearer ${token}`).expect(401);
      assert.equal(res.body.error.code, 'UNAUTHENTICATED');
    }
  });

  let created;
  await t.test('create stores the image and answers the ad', async () => {
    const before = storage.calls.length;
    const res = await post('/ads', valid()).expect(201);
    const { ad } = res.body.data;
    created = ad;
    assert.deepEqual(Object.keys(ad).sort(), AD_KEYS);
    const [put] = storage.calls.slice(before);
    assert.equal(put[0], 'put');
    assert.match(put[1], KEY);
    assert.ok(put[1].endsWith('.jpg'));
    assert.equal(put[2], 'image/jpeg');
    assert.deepEqual(storage.files.get(put[1]), JPEG);
    assert.deepEqual(ad, {
      id: ad.id,
      title: 'Protein bar promo',
      imageUrl: `/storage/${put[1]}`,
      linkUrl: 'https://example.com/bar',
      advertiser: 'Bar Co.',
      amountPhp: 1200.5,
      startsOn: manilaDay(1),
      endsOn: manilaDay(-29),
      active: true,
      status: 'running',
      views: 0,
      taps: 0,
    });
    const row = await adRow(ad.id);
    assert.equal(row.image_url, put[1], 'the key is stored, not the URL');
    assert.equal(row.added_by, adminId);
    assert.equal(row.is_active, 1);
    assert.equal(row.amount_php, '1200.50');
  });

  await t.test('a PNG is stored as .png; no link is null; names are trimmed', async () => {
    const before = storage.calls.length;
    const { ad } = (await post('/ads', valid({
      image: b64(PNG), mimeType: 'image/png', linkUrl: undefined, title: '  Gym gear  ', advertiser: ' Gear PH ',
    })).expect(201)).body.data;
    const [put] = storage.calls.slice(before);
    assert.ok(put[1].endsWith('.png'));
    assert.equal(put[2], 'image/png');
    assert.equal(ad.linkUrl, null);
    assert.equal(ad.title, 'Gym gear');
    assert.equal(ad.advertiser, 'Gear PH');
    const { ad: blank } = (await post('/ads', valid({ linkUrl: null })).expect(201)).body.data;
    assert.equal(blank.linkUrl, null);
  });

  await t.test('each bad field is 400 INVALID_ADMIN_FIELD naming that field, and nothing is stored', async () => {
    const before = storage.calls.length;
    const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM advertisements');
    const cases = [
      [{ title: undefined }, 'title'],
      [{ title: '   ' }, 'title'],
      [{ title: 'x'.repeat(81) }, 'title'],
      [{ title: 5 }, 'title'],
      [{ advertiser: undefined }, 'advertiser'],
      [{ advertiser: '' }, 'advertiser'],
      [{ advertiser: 'x'.repeat(121) }, 'advertiser'],
      [{ amountPhp: undefined }, 'amountPhp'],
      [{ amountPhp: '100' }, 'amountPhp'],
      [{ amountPhp: -1 }, 'amountPhp'],
      [{ amountPhp: 1_000_000.01 }, 'amountPhp'],
      [{ amountPhp: 10.005 }, 'amountPhp'],
      [{ startsOn: undefined }, 'startsOn'],
      [{ startsOn: '2026-02-30' }, 'startsOn'],
      [{ startsOn: '2026-13-01' }, 'startsOn'],
      [{ startsOn: '2026-1-01' }, 'startsOn'],
      [{ endsOn: undefined }, 'endsOn'],
      [{ endsOn: 'tomorrow' }, 'endsOn'],
      [{ startsOn: '2026-11-10', endsOn: '2026-11-09' }, 'endsOn'],
      [{ linkUrl: 'http://example.com' }, 'linkUrl'],
      [{ linkUrl: 'javascript:alert(1)' }, 'linkUrl'],
      [{ linkUrl: 'not a url' }, 'linkUrl'],
      [{ linkUrl: `https://example.com/${'a'.repeat(481)}` }, 'linkUrl'],
      [{ linkUrl: 7 }, 'linkUrl'],
    ];
    for (const [over, field] of cases) {
      assert.equal(fieldOf(await post('/ads', valid(over))), field, JSON.stringify(over));
    }
    assert.equal(storage.calls.length, before);
    const [[{ n: after }]] = await pool.query('SELECT COUNT(*) AS n FROM advertisements');
    assert.equal(after, n);
  });

  await t.test('a link is stored as the address the app will open (normalised by URL)', async () => {
    const cases = [
      ['https:example.com', 'https://example.com/'],
      ['https:/example.com', 'https://example.com/'],
      ['https://exa\tmple.com/x', 'https://example.com/x'],
      ['https://example.com/a\nb', 'https://example.com/ab'],
      ['  HTTPS://Example.COM/Bar  ', 'https://example.com/Bar'],
    ];
    for (const [typed, stored] of cases) {
      const { ad } = (await post('/ads', valid({ linkUrl: typed })).expect(201)).body.data;
      assert.equal(ad.linkUrl, stored, JSON.stringify(typed));
      assert.equal((await adRow(ad.id)).link_url, stored, JSON.stringify(typed));
    }
    // The 500 limit is on the stored address: a space becomes %20.
    const typed500 = `https://example.com/${'a'.repeat(478)} b`;
    assert.equal(typed500.length, 500);
    assert.equal(fieldOf(await post('/ads', valid({ linkUrl: typed500 }))), 'linkUrl');
    // PATCH stores the same normalised address.
    const { ad } = (await post('/ads', valid()).expect(201)).body.data;
    assert.equal(
      (await patch(`/ads/${ad.id}`, { linkUrl: 'https:example.com' }).expect(200)).body.data.ad.linkUrl,
      'https://example.com/',
    );
    assert.equal((await adRow(ad.id)).link_url, 'https://example.com/');
  });

  await t.test('the edges pass: 80/120 characters, ₱0 and ₱1,000,000, one day, a 500-character link', async () => {
    await post('/ads', valid({
      title: 'x'.repeat(80), advertiser: 'y'.repeat(120), amountPhp: 0, startsOn: '2026-12-01', endsOn: '2026-12-01',
      linkUrl: `https://example.com/${'a'.repeat(480)}`,
    })).expect(201);
    const { ad } = (await post('/ads', valid({ amountPhp: 1_000_000, startsOn: '2030-01-01', endsOn: '2030-02-01' }))
      .expect(201)).body.data;
    assert.equal(ad.amountPhp, 1_000_000);
    assert.equal(ad.status, 'scheduled', 'a future start is allowed');
  });

  await t.test('a missing or bad image on create is 400 INVALID_IMAGE', async () => {
    for (const over of [
      { image: undefined, mimeType: undefined },
      { image: undefined },
      { mimeType: 'image/gif' },
      { image: b64(PNG) },
    ]) {
      const res = await post('/ads', valid(over)).expect(400);
      assert.equal(res.body.error.code, 'INVALID_IMAGE');
    }
    const big = Buffer.alloc(1_500_001);
    JPEG.copy(big);
    const res = await post('/ads', valid({ image: b64(big) })).expect(400);
    assert.equal(res.body.error.message, 'The image must be at most 1.5 MB.');
  });

  await t.test('a 1.4 MB image fits the route\'s body limit', async () => {
    const photo = Buffer.alloc(1_400_000);
    JPEG.copy(photo);
    await post('/ads', valid({ image: b64(photo) })).expect(201);
  });

  await t.test('status, first match wins: Paused, then Scheduled, then Ended, else Running', async () => {
    const row = (isActive, startsOn, endsOn) => ({ is_active: isActive, starts_on: startsOn, ends_on: endsOn });
    assert.equal(adStatus(row(0, manilaDay(-1), manilaDay(-5)), today), 'paused', 'paused even before its start');
    assert.equal(adStatus(row(0, manilaDay(9), manilaDay(5)), today), 'paused', 'paused even after its end');
    assert.equal(adStatus(row(1, manilaDay(-1), manilaDay(-5)), today), 'scheduled');
    assert.equal(adStatus(row(1, manilaDay(9), manilaDay(1)), today), 'ended');
    assert.equal(adStatus(row(1, today, today), today), 'running', 'start and end days are run days');
    assert.equal(adStatus(row(1, manilaDay(1), manilaDay(-1)), today), 'running');
  });

  await t.test('the list is newest first with each ad\'s status', async () => {
    await pool.query('DELETE FROM advertisements');
    const add = async (title, over) => (await post('/ads', valid({ title, ...over })).expect(201)).body.data.ad.id;
    const running = await add('Running', {});
    const scheduled = await add('Scheduled', { startsOn: manilaDay(-1), endsOn: manilaDay(-10) });
    const ended = await add('Ended', { startsOn: manilaDay(10), endsOn: manilaDay(1) });
    const paused = await add('Paused', {});
    await patch(`/ads/${paused}`, { active: false }).expect(200);
    await pool.query('UPDATE advertisements SET views = 1204, taps = 37 WHERE ad_id = ?', [running]);

    const { ads } = (await get('/ads').expect(200)).body.data;
    assert.deepEqual(ads.map((a) => [a.id, a.status]), [
      [paused, 'paused'], [ended, 'ended'], [scheduled, 'scheduled'], [running, 'running'],
    ]);
    const r = ads.find((a) => a.id === running);
    assert.deepEqual(Object.keys(r).sort(), AD_KEYS);
    assert.deepEqual([r.views, r.taps], [1204, 37]);
    assert.equal(ads.find((a) => a.id === paused).active, false);
  });

  await t.test('PATCH changes only the fields sent', async () => {
    const { ad } = (await post('/ads', valid()).expect(201)).body.data;
    const before = await adRow(ad.id);
    const { ad: edited } = (await patch(`/ads/${ad.id}`, { title: 'New title', amountPhp: 99.99 }).expect(200)).body.data;
    assert.deepEqual(edited, { ...ad, title: 'New title', amountPhp: 99.99 });
    const after = await adRow(ad.id);
    assert.deepEqual({ ...after, title: before.title, amount_php: before.amount_php }, before);
    // An empty PATCH changes nothing.
    assert.deepEqual((await patch(`/ads/${ad.id}`, {}).expect(200)).body.data.ad, edited);
    // linkUrl: null removes the link.
    assert.equal((await patch(`/ads/${ad.id}`, { linkUrl: null }).expect(200)).body.data.ad.linkUrl, null);
  });

  await t.test('PATCH validates what it is sent, end against the stored start', async () => {
    const { ad } = (await post('/ads', valid({ startsOn: '2026-12-10', endsOn: '2026-12-20' })).expect(201)).body.data;
    assert.equal(fieldOf(await patch(`/ads/${ad.id}`, { title: '' })), 'title');
    assert.equal(fieldOf(await patch(`/ads/${ad.id}`, { amountPhp: -5 })), 'amountPhp');
    assert.equal(fieldOf(await patch(`/ads/${ad.id}`, { linkUrl: 'ftp://x.com' })), 'linkUrl');
    assert.equal(fieldOf(await patch(`/ads/${ad.id}`, { endsOn: '2026-12-09' })), 'endsOn');
    assert.equal(fieldOf(await patch(`/ads/${ad.id}`, { startsOn: '2026-12-21' })), 'endsOn');
    assert.equal(fieldOf(await patch(`/ads/${ad.id}`, { active: 'no' })), 'active');
    const res = await patch(`/ads/${ad.id}`, { mimeType: 'image/png' }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_IMAGE');
    // Both dates moved together past the old end are fine.
    const { ad: moved } = (await patch(`/ads/${ad.id}`, { startsOn: '2027-01-01', endsOn: '2027-01-31' })
      .expect(200)).body.data;
    assert.deepEqual([moved.startsOn, moved.endsOn], ['2027-01-01', '2027-01-31']);
  });

  await t.test('PATCH with a new image stores it and deletes the old file', async () => {
    const { ad } = (await post('/ads', valid()).expect(201)).body.data;
    const oldKey = (await adRow(ad.id)).image_url;
    const before = storage.calls.length;
    const { ad: edited } = (await patch(`/ads/${ad.id}`, { image: b64(PNG), mimeType: 'image/png' }).expect(200))
      .body.data;
    const newKey = (await adRow(ad.id)).image_url;
    assert.match(newKey, KEY);
    assert.ok(newKey.endsWith('.png'));
    assert.notEqual(newKey, oldKey);
    assert.equal(edited.imageUrl, `/storage/${newKey}`);
    assert.deepEqual(storage.calls.slice(before), [['put', newKey, 'image/png'], ['delete', oldKey]]);
    assert.equal(storage.files.has(oldKey), false);
    assert.deepEqual(storage.files.get(newKey), PNG);
  });

  await t.test('active: false pauses and active: true resumes', async () => {
    const { ad } = (await post('/ads', valid()).expect(201)).body.data;
    const paused = (await patch(`/ads/${ad.id}`, { active: false }).expect(200)).body.data.ad;
    assert.deepEqual([paused.active, paused.status], [false, 'paused']);
    const resumed = (await patch(`/ads/${ad.id}`, { active: true }).expect(200)).body.data.ad;
    assert.deepEqual([resumed.active, resumed.status], [true, 'running']);
  });

  await t.test('PATCH of an unknown ad is 404 AD_NOT_FOUND', async () => {
    for (const id of ['999999', 'abc', '0']) {
      const res = await patch(`/ads/${id}`, { active: false }).expect(404);
      assert.equal(res.body.error.code, 'AD_NOT_FOUND');
      assert.equal(res.body.error.message, 'No such ad.');
    }
  });

  await t.test('listAdsForMonth lists the ads that start in that month, for Revenue', async () => {
    await pool.query('DELETE FROM advertisements');
    const add = async (title, startsOn, endsOn, amountPhp) => (await post('/ads', valid({
      title, advertiser: `${title} Inc.`, startsOn, endsOn, amountPhp,
    })).expect(201)).body.data.ad.id;
    const nov = await add('Nov', '2026-11-01', '2026-11-30', 1200);
    const late = await add('Late Nov', '2026-11-30', '2026-12-15', 300.25);
    await add('Oct', '2026-10-31', '2026-11-05', 500);
    await add('Dec', '2026-12-01', '2026-12-31', 800);
    assert.deepEqual(await listAdsForMonth(pool, '2026-11'), [
      { adId: nov, advertiser: 'Nov Inc.', title: 'Nov', amountPhp: 1200, startsOn: '2026-11-01', endsOn: '2026-11-30' },
      {
        adId: late, advertiser: 'Late Nov Inc.', title: 'Late Nov', amountPhp: 300.25, startsOn: '2026-11-30', endsOn: '2026-12-15',
      },
    ]);
    assert.deepEqual(await listAdsForMonth(pool, '2027-01'), []);
  });
});
