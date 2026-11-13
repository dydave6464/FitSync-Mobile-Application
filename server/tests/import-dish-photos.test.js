'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createStorage } = require('../src/services/storage');
const { importDishPhotos } = require('../src/db/dish-photos');

// Tiny images built here, never files in git: the magic bytes and padding.
const JPEG = Buffer.from([0xff, 0xd8, 0xff, ...Array(64).fill(0)]);
const JPEG_2 = Buffer.from([0xff, 0xd8, 0xff, ...Array(64).fill(1)]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d]);
const NOT_AN_IMAGE = Buffer.from('GIF89a, not a JPEG or PNG');
const TOO_BIG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(1_500_000)]);
const KEY = /^foods\/[0-9a-f-]{36}\.(jpg|png)$/;

// A private folder the way the user keeps it: photos/ plus manifest.json.
function makeFolder(entries, files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dish-photos-'));
  fs.mkdirSync(path.join(dir, 'photos'));
  for (const [name, bytes] of Object.entries(files)) fs.writeFileSync(path.join(dir, 'photos', name), bytes);
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(entries));
  return dir;
}

test('importDishPhotos', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const storageDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dish-photos-storage-'));
  const storage = createStorage({ mode: 'local', localDir: storageDir });
  const folders = [];
  const folder = (entries, files) => { const d = makeFolder(entries, files); folders.push(d); return d; };
  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
    fs.rmSync(storageDir, { recursive: true, force: true });
    for (const d of folders) fs.rmSync(d, { recursive: true, force: true });
  });

  const insert = async (name, photoKey = null) => {
    const [r] = await pool.query(
      `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, photo_key)
       VALUES (?, 'filipino', '1 cup', 300, 20, 10, 15, ?)`,
      [name, photoKey],
    );
    return r.insertId;
  };
  const photoKeyOf = async (id) => (await pool.query('SELECT photo_key FROM foods WHERE food_id = ?', [id]))[0][0].photo_key;
  const stored = (key) => path.join(storageDir, key);

  const adobo = await insert('Chicken adobo');
  const sinigang = await insert('Sinigang');
  // A FatSecret copy with the same name as FitSync's own Sinigang: never the one linked.
  const sinigangCopy = await insert('Sinigang');
  await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'fs-sin')", [sinigangCopy]);
  // A dish that exists only as a FatSecret copy.
  const bananaCopy = await insert('Banana');
  await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'fs-ban')", [bananaCopy]);
  // A dish that already has a photo.
  await storage.put('foods/already.jpg', JPEG, 'image/jpeg');
  const turon = await insert('Turon', 'foods/already.jpg');

  const good = folder(
    [
      { dish: 'Chicken adobo', file: 'photos/chicken-adobo.jpg', source: 'web' },
      { dish: 'Sinigang', file: 'photos/sinigang.png' },
      { dish: 'Turon', file: 'photos/turon.jpg' },
    ],
    { 'chicken-adobo.jpg': JPEG, 'sinigang.png': PNG, 'turon.jpg': JPEG_2 },
  );

  let firstKeys;
  await t.test('imports every listed dish that exists; one that has a photo is skipped', async () => {
    const lines = [];
    const summary = await importDishPhotos({ pool, storage, dir: good, log: (l) => lines.push(l) });
    assert.deepEqual(summary, { imported: ['Chicken adobo', 'Sinigang'], skipped: ['Turon'], notFound: [], bad: [] });
    assert.equal(lines.length, 3, 'one line per dish');

    const adoboKey = await photoKeyOf(adobo);
    const sinigangKey = await photoKeyOf(sinigang);
    assert.match(adoboKey, /^foods\/[0-9a-f-]{36}\.jpg$/);
    assert.match(sinigangKey, /^foods\/[0-9a-f-]{36}\.png$/);
    assert.deepEqual(fs.readFileSync(stored(adoboKey)), JPEG);
    assert.deepEqual(fs.readFileSync(stored(sinigangKey)), PNG);
    assert.equal(await photoKeyOf(sinigangCopy), null, 'the FatSecret copy is never linked');
    assert.equal(await photoKeyOf(turon), 'foods/already.jpg', 'the existing photo is kept');
    assert.ok(fs.existsSync(stored('foods/already.jpg')));
    firstKeys = { adoboKey, sinigangKey };
  });

  await t.test('a second run imports nothing: all skipped (has a photo)', async () => {
    const summary = await importDishPhotos({ pool, storage, dir: good });
    assert.deepEqual(summary, { imported: [], skipped: ['Chicken adobo', 'Sinigang', 'Turon'], notFound: [], bad: [] });
    assert.equal(await photoKeyOf(adobo), firstKeys.adoboKey);
    assert.equal(await photoKeyOf(sinigang), firstKeys.sinigangKey);
  });

  await t.test('replace: true re-imports them and deletes the previous files', async () => {
    const summary = await importDishPhotos({ pool, storage, dir: good, replace: true });
    assert.deepEqual(summary, { imported: ['Chicken adobo', 'Sinigang', 'Turon'], skipped: [], notFound: [], bad: [] });
    const adoboKey = await photoKeyOf(adobo);
    const turonKey = await photoKeyOf(turon);
    assert.match(adoboKey, KEY);
    assert.notEqual(adoboKey, firstKeys.adoboKey);
    assert.notEqual(await photoKeyOf(sinigang), firstKeys.sinigangKey);
    assert.match(turonKey, KEY);
    assert.deepEqual(fs.readFileSync(stored(turonKey)), JPEG_2);
    assert.equal(fs.existsSync(stored(firstKeys.adoboKey)), false);
    assert.equal(fs.existsSync(stored(firstKeys.sinigangKey)), false);
    assert.equal(fs.existsSync(stored('foods/already.jpg')), false);
  });

  await t.test('a name with no FitSync food, or only a FatSecret copy, is not found', async () => {
    const dir = folder(
      [
        { dish: 'Lechon kawali', file: 'photos/lechon.jpg' },
        { dish: 'Banana', file: 'photos/banana.jpg' },
        { dish: 'chicken adobo', file: 'photos/lower.jpg' },
      ],
      { 'lechon.jpg': JPEG, 'banana.jpg': JPEG, 'lower.jpg': JPEG },
    );
    const before = fs.readdirSync(path.join(storageDir, 'foods')).length;
    const summary = await importDishPhotos({ pool, storage, dir, replace: true });
    assert.deepEqual(summary, {
      imported: [], skipped: [], notFound: ['Lechon kawali', 'Banana', 'chicken adobo'], bad: [],
    });
    assert.equal(await photoKeyOf(bananaCopy), null);
    assert.equal(fs.readdirSync(path.join(storageDir, 'foods')).length, before, 'nothing stored');
  });

  await t.test('a file that is not JPEG/PNG, over 1.5 MB or missing is bad; nothing stored for it', async () => {
    const keep = await photoKeyOf(adobo);
    const sinigangKeep = await photoKeyOf(sinigang);
    const turonKeep = await photoKeyOf(turon);
    const dir = folder(
      [
        { dish: 'Chicken adobo', file: 'photos/adobo.gif' },
        { dish: 'Sinigang', file: 'photos/huge.jpg' },
        { dish: 'Turon', file: 'photos/missing.jpg' },
      ],
      { 'adobo.gif': NOT_AN_IMAGE, 'huge.jpg': TOO_BIG },
    );
    const before = fs.readdirSync(path.join(storageDir, 'foods')).sort();
    const summary = await importDishPhotos({ pool, storage, dir, replace: true });
    assert.deepEqual(summary, { imported: [], skipped: [], notFound: [], bad: ['Chicken adobo', 'Sinigang', 'Turon'] });
    assert.deepEqual(fs.readdirSync(path.join(storageDir, 'foods')).sort(), before, 'nothing stored');
    assert.equal(await photoKeyOf(adobo), keep);
    assert.equal(await photoKeyOf(sinigang), sinigangKeep);
    assert.equal(await photoKeyOf(turon), turonKeep);
  });

  await t.test('an entry with "file": null is ignored', async () => {
    const dir = folder([{ dish: 'Chicken adobo', file: null }, { dish: 'Lechon kawali', file: null }], {});
    const lines = [];
    const summary = await importDishPhotos({ pool, storage, dir, replace: true, log: (l) => lines.push(l) });
    assert.deepEqual(summary, { imported: [], skipped: [], notFound: [], bad: [] });
    assert.deepEqual(lines, []);
  });

  await t.test('a missing folder or manifest throws an error naming the path', async () => {
    const missing = path.join(os.tmpdir(), 'dish-photos-does-not-exist-xyz');
    await assert.rejects(importDishPhotos({ pool, storage, dir: missing }), (err) => err.message.includes(missing));
    const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'dish-photos-'));
    folders.push(empty);
    await assert.rejects(
      importDishPhotos({ pool, storage, dir: empty }),
      (err) => err.message.includes(path.join(empty, 'manifest.json')),
    );
  });

  await t.test('an unreadable manifest throws an error naming the path', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dish-photos-'));
    folders.push(dir);
    fs.writeFileSync(path.join(dir, 'manifest.json'), '{ not json');
    await assert.rejects(
      importDishPhotos({ pool, storage, dir }),
      (err) => err.message.includes(path.join(dir, 'manifest.json')),
    );
  });
});
