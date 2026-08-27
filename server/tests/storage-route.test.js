'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const request = require('supertest');
const { createStorage } = require('../src/services/storage');
const { buildTestApp } = require('./helpers/test-app');

const GIF = Buffer.concat([Buffer.from('GIF89a', 'ascii'), Buffer.from([0x01, 0x02, 0x03])]);

test('storage media route', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'fitsync-storage-'));
  const storage = createStorage({ mode: 'local', localDir: root });
  await storage.put('exercises/0001/animation.gif', GIF, 'image/gif');

  const app = buildTestApp({
    pool: null,
    storage,
    storageConfig: { mode: 'local', localDir: root },
  });

  t.after(async () => {
    await fs.rm(root, { recursive: true, force: true });
  });

  await t.test('serves a stored file byte for byte', async () => {
    const res = await request(app).get('/storage/exercises/0001/animation.gif').expect(200);
    assert.deepEqual(Buffer.from(res.body), GIF);
  });

  await t.test('a missing key is a 404 in the error envelope', async () => {
    const res = await request(app).get('/storage/exercises/9999/animation.gif').expect(404);
    assert.ok(res.body.error, 'must use the error envelope, not an HTML page');
  });

  await t.test('refuses to traverse out of the storage root', async () => {
    // Encoded so the path survives to Express rather than being collapsed by
    // the HTTP client.
    const res = await request(app).get('/storage/..%2f..%2f..%2fetc%2fpasswd');
    assert.notEqual(res.status, 200);
    assert.ok(!String(res.text || '').includes('root:'), 'must not serve host files');
  });

  await t.test('the API surface is unaffected', async () => {
    await request(app).get('/api/v1/exercises/filters').expect(500);
  });
});
