'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Writable } = require('node:stream');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { createLogger } = require('../src/lib/logger');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const { VisionError } = require('../src/services/vision/errors');

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d]);
// A photo whose base64 is easy to look for in rows and log lines.
const MARKED = Buffer.concat([JPEG, Buffer.from('FITSYNC-PHOTO-MARKER-'.repeat(20))]);
const b64 = (buf) => buf.toString('base64');
const PHOTO = { image: b64(JPEG), mimeType: 'image/jpeg' };

function captureLogger() {
  let output = '';
  const destination = new Writable({ write(chunk, _enc, cb) { output += chunk.toString(); cb(); } });
  return { logger: createLogger({ level: 'info', env: 'production', destination }), text: () => output };
}

test('POST /nutrition/recognize', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const calls = [];
  let answer = async () => ({ items: [] });
  const vision = { model: 'fake', async recognize(args) { calls.push(args); return answer(args); } };
  const captured = captureLogger();
  const app = buildTestApp({ pool, vision, logger: captured.logger });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const food = async (name, servingDesc, kcal) => (await pool.query(
    `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, fiber_g)
     VALUES (?, 'filipino', ?, ?, 4, 40, 1, 0.5)`,
    [name, servingDesc, kcal],
  ))[0].insertId;
  const RICE = await food('White rice', '1 cup (160 g)', 206);
  await food('Garlic fried rice (sinangag)', '1 cup (160 g)', 299);
  // A FatSecret copy someone has logged: on the menu, flagged fromFatsecret.
  const [mango] = await pool.query("INSERT INTO foods (name, category, serving_desc, calories) VALUES ('Mango Shake', 'international', '1 glass', 250)");
  await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'fs-1')", [mango.insertId]);
  const [someone] = await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('someone@b.com', 'x', 'S')");
  await pool.query(
    "INSERT INTO meal_logs (user_id, food_id, meal_type, servings, calories, logged_via, log_date) VALUES (?, ?, 'snack', 1, 250, 'search', CURDATE())",
    [someone.insertId, mango.insertId],
  );

  let seq = 0;
  const freshUser = async ({ pro }) => {
    seq += 1;
    const email = `snap${seq}@example.com`;
    const reg = await request(app).post('/api/v1/auth/register').send({ email, password: 's3cret-pass', fullName: 'S' }).expect(201);
    const userId = reg.body.data.user.userId;
    await markEmailVerified(pool, userId);
    if (pro) await pool.query('UPDATE users SET is_premium = 1 WHERE user_id = ?', [userId]);
    const login = await request(app).post('/api/v1/auth/login').send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return { userId, recognize: (body) => request(app).post('/api/v1/nutrition/recognize').set(auth).send(body) };
  };
  const rowsOf = async (userId) => (await pool.query('SELECT status FROM photo_recognitions WHERE user_id = ? ORDER BY recognition_id', [userId]))[0].map((r) => r.status);

  await t.test('signed out is 401; a free account is 403 PRO_REQUIRED and the AI is not asked', async () => {
    await request(app).post('/api/v1/nutrition/recognize').send(PHOTO).expect(401);
    const u = await freshUser({ pro: false });
    const res = await u.recognize(PHOTO).expect(403);
    assert.equal(res.body.error.code, 'PRO_REQUIRED');
    assert.equal(calls.length, 0);
  });

  await t.test('answers with the matched items, their servings, alternatives and what is not on the list', async () => {
    const u = await freshUser({ pro: true });
    answer = async () => ({ items: [
      { menu: 'White rice', name: 'White rice', quantity: 1, unit: 'cup', grams: 240, confidence: 0.95, alternatives: ['Garlic fried rice (sinangag)'] },
      { menu: 'Mango Shake', name: 'Mango Shake', quantity: 1, unit: 'glass', grams: null, confidence: 0.7, alternatives: [] },
      { menu: null, name: 'Atchara (pickled papaya)', quantity: 1, unit: 'tbsp', grams: 15, confidence: 0.4, alternatives: [] },
    ] });
    const d = (await u.recognize(PHOTO).expect(200)).body.data;
    assert.equal(d.remainingToday, 14);
    assert.deepEqual(d.items[0].food, {
      id: RICE, name: 'White rice', servingDesc: '1 cup (160 g)', fromFatsecret: false,
      perServing: { kcal: 206, proteinG: 4, carbsG: 40, fatG: 1, fiberG: 0.5, sugarG: null, sodiumMg: null },
    });
    assert.deepEqual(d.items.map((i) => [i.food.name, i.servings, i.confidence, i.food.fromFatsecret]), [
      ['White rice', 1.5, 0.95, false], ['Mango Shake', 1, 0.7, true],
    ]);
    assert.deepEqual(d.items[0].alternatives.map((a) => a.name), ['Garlic fried rice (sinangag)']);
    assert.deepEqual(d.unlisted.map((x) => x.name), ['Atchara (pickled papaya)']);

    const sent = calls.at(-1);
    assert.equal(sent.imageBase64, PHOTO.image);
    assert.equal(sent.mimeType, 'image/jpeg');
    assert.ok(sent.menuNames.includes('White rice') && sent.menuNames.includes('Mango Shake'));

    const [items] = await pool.query(
      'SELECT item_id, suggested_food_id, suggested_servings FROM photo_recognition_items WHERE recognition_id = ? ORDER BY item_order',
      [d.recognitionId],
    );
    assert.deepEqual(items.map((r) => r.item_id), [...d.items.map((i) => i.itemId), ...d.unlisted.map((x) => x.itemId)]);
    assert.deepEqual(items.map((r) => r.suggested_food_id), [RICE, mango.insertId, null]);
    assert.deepEqual(await rowsOf(u.userId), ['recognised']);
  });

  await t.test('no food found is a 200 with nothing in it, recorded as empty', async () => {
    const u = await freshUser({ pro: true });
    answer = async () => ({ items: [] });
    const d = (await u.recognize(PHOTO).expect(200)).body.data;
    assert.deepEqual([d.items, d.unlisted], [[], []]);
    assert.deepEqual(await rowsOf(u.userId), ['empty']);
  });

  await t.test('a photo that is not a JPEG or PNG of at most 1.5 MB is 400 INVALID_IMAGE, before the AI or the limit', async () => {
    const u = await freshUser({ pro: true });
    const before = calls.length;
    const big = Buffer.alloc(1_500_003);
    JPEG.copy(big);
    for (const body of [
      { image: PHOTO.image },
      { image: PHOTO.image, mimeType: 'image/gif' },
      { image: `data:image/jpeg;base64,${PHOTO.image}`, mimeType: 'image/jpeg' },
      { image: b64(PNG), mimeType: 'image/jpeg' },
      { image: PHOTO.image, mimeType: 'image/png' },
      { image: '', mimeType: 'image/jpeg' },
      { image: b64(big), mimeType: 'image/jpeg' },
    ]) {
      const res = await u.recognize(body).expect(400);
      assert.equal(res.body.error.code, 'INVALID_IMAGE');
    }
    assert.equal(calls.length, before);
    assert.deepEqual(await rowsOf(u.userId), []);
    await u.recognize({ image: b64(PNG), mimeType: 'image/png' }).expect(200);
  });

  await t.test('a body over 2 MB is 413 PAYLOAD_TOO_LARGE', async () => {
    const u = await freshUser({ pro: true });
    const res = await u.recognize({ image: b64(Buffer.alloc(1_700_000)), mimeType: 'image/jpeg' }).expect(413);
    assert.equal(res.body.error.code, 'PAYLOAD_TOO_LARGE');
  });

  await t.test('the 15th photo of the day is allowed, the 16th is 429, and failed attempts never count', async () => {
    const u = await freshUser({ pro: true });
    const values = (n, status) => pool.query(
      `INSERT INTO photo_recognitions (user_id, item_count, status) VALUES ${Array(n).fill(`(?, 0, '${status}')`).join(', ')}`,
      Array(n).fill(u.userId),
    );
    await values(14, 'recognised');
    await values(20, 'failed');
    answer = async () => ({ items: [] });
    assert.equal((await u.recognize(PHOTO).expect(200)).body.data.remainingToday, 0);
    const before = calls.length;
    const res = await u.recognize(PHOTO).expect(429);
    assert.equal(res.body.error.code, 'PHOTO_LIMIT_REACHED');
    assert.equal(res.body.error.message, "You've used today's meal photos. Try again tomorrow.");
    assert.equal(calls.length, before, 'refused before the AI is asked');
  });

  await t.test('the AI busy is 503, down or broken is 502; each leaves a failed row that does not count', async () => {
    const u = await freshUser({ pro: true });
    answer = async () => { throw new VisionError('VISION_BUSY'); };
    assert.equal((await u.recognize(PHOTO).expect(503)).body.error.code, 'VISION_BUSY');
    answer = async () => { throw new VisionError('VISION_UNAVAILABLE'); };
    assert.equal((await u.recognize(PHOTO).expect(502)).body.error.code, 'VISION_UNAVAILABLE');
    answer = async () => { throw new Error('boom'); };
    assert.equal((await u.recognize(PHOTO).expect(502)).body.error.code, 'VISION_UNAVAILABLE');
    // A dead key (401) is logged by its status, so it can be told from an outage.
    answer = async () => { throw new VisionError('VISION_UNAVAILABLE', { status: 401 }); };
    assert.equal((await u.recognize({ image: b64(MARKED), mimeType: 'image/jpeg' }).expect(502)).body.error.code, 'VISION_UNAVAILABLE');
    const failed = captured.text().split('\n').filter((l) => l.includes('meal photo recognition failed'));
    const dead = failed.find((l) => l.includes('"status":401'));
    assert.ok(dead, 'the 401 is logged with its status');
    assert.ok(dead.includes('"code":"VISION_UNAVAILABLE"'));
    assert.ok(failed.some((l) => l.includes('"code":"VISION_BUSY"')), 'a busy failure is logged too');
    assert.ok(!captured.text().includes(b64(MARKED).slice(16, 80)), 'no log line holds the photo');
    // Groq busy and the Cloudflare backup refusing its token: both are logged.
    answer = async () => {
      const err = new VisionError('VISION_BUSY', { status: 429 });
      err.backup = new VisionError('VISION_UNAVAILABLE', { status: 401 });
      throw err;
    };
    assert.equal((await u.recognize(PHOTO).expect(503)).body.error.code, 'VISION_BUSY');
    const both = captured.text().split('\n').filter((l) => l.includes('meal photo recognition failed')).at(-1);
    assert.ok(both.includes('"status":429') && both.includes('"backupCode":"VISION_UNAVAILABLE"') && both.includes('"backupStatus":401'), both);
    assert.deepEqual(await rowsOf(u.userId), ['failed', 'failed', 'failed', 'failed', 'failed']);
    answer = async () => ({ items: [] });
    assert.equal((await u.recognize(PHOTO).expect(200)).body.data.remainingToday, 14);
  });

  await t.test('with vision off (a stub in production) it is 502 and nothing is recorded', async () => {
    const off = buildTestApp({ pool, vision: null });
    const u = await freshUser({ pro: true });
    const login = await request(off).post('/api/v1/auth/login').send({ email: `snap${seq}@example.com`, password: 's3cret-pass' }).expect(200);
    const res = await request(off).post('/api/v1/nutrition/recognize')
      .set({ Authorization: `Bearer ${login.body.data.token}` }).send(PHOTO).expect(502);
    assert.equal(res.body.error.code, 'VISION_UNAVAILABLE');
    assert.deepEqual(await rowsOf(u.userId), []);
  });

  await t.test('when the app stops waiting, the photo is cancelled and nothing is recorded', async () => {
    const u = await freshUser({ pro: true });
    let sawCancel;
    const cancelled = new Promise((resolve) => { sawCancel = resolve; });
    // Stands in for a recogniser waiting out Groq's busy reply: it finishes
    // only when told the app has left.
    answer = ({ signal }) => new Promise((_, reject) => {
      signal.addEventListener('abort', () => { sawCancel(true); reject(new VisionError('VISION_CANCELLED')); });
    });
    await assert.rejects(u.recognize(PHOTO).timeout(200));
    assert.equal(await cancelled, true, 'the recogniser was told to stop');
    await new Promise((r) => setTimeout(r, 100));
    assert.deepEqual(await rowsOf(u.userId), [], 'not counted, not recorded as failed');
    answer = async () => ({ items: [] });
  });

  await t.test('the photo is never stored or logged', async () => {
    const u = await freshUser({ pro: true });
    answer = async () => ({ items: [{ menu: 'White rice', name: 'White rice', quantity: 1, unit: 'cup', grams: 160, confidence: 0.9, alternatives: [] }], provider: 'cloudflare',
      failed: [{ provider: 'groq', code: 'VISION_UNAVAILABLE', status: 401, cause: null }] });
    await u.recognize({ image: b64(MARKED), mimeType: 'image/jpeg' }).expect(200);
    const needle = b64(MARKED).slice(16, 80);
    const [recs] = await pool.query('SELECT * FROM photo_recognitions WHERE user_id = ?', [u.userId]);
    const [items] = await pool.query(
      'SELECT i.* FROM photo_recognition_items i JOIN photo_recognitions r ON r.recognition_id = i.recognition_id WHERE r.user_id = ?',
      [u.userId],
    );
    assert.ok(!JSON.stringify([recs, items]).includes(needle), 'no row holds the photo');
    const recognised = captured.text().split('\n').filter((l) => l.includes('meal photo recognised')).at(-1);
    assert.ok(recognised, 'the request was logged');
    assert.ok(recognised.includes('"provider":"cloudflare"'), 'with the service that answered');
    assert.ok(recognised.includes('"failed":[{"provider":"groq","code":"VISION_UNAVAILABLE","status":401,"cause":null}]'),
      'and why the other did not, so a dead Groq key shows while Cloudflare covers for it');
    assert.ok(!captured.text().includes(needle), 'no log line holds the photo');
  });
});
