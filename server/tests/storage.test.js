'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createStorage } = require('../src/services/storage');

function tmpStorage() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fitsync-storage-'));
  return { dir, storage: createStorage({ mode: 'local', localDir: dir }) };
}

test('round-trips a file', async () => {
  const { dir, storage } = tmpStorage();
  try {
    const key = await storage.put('exercises/squat.gif', Buffer.from('GIF89a'));
    assert.equal(key, 'exercises/squat.gif');
    assert.equal((await storage.get('exercises/squat.gif')).toString(), 'GIF89a');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('put accepts a contentType argument that the local driver ignores', async () => {
  const { dir, storage } = tmpStorage();
  try {
    const key = await storage.put('exercises/squat.gif', Buffer.from('GIF89a'), 'image/gif');
    assert.equal(key, 'exercises/squat.gif');
    assert.equal((await storage.get('exercises/squat.gif')).toString(), 'GIF89a');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('creates nested directories on write', async () => {
  const { dir, storage } = tmpStorage();
  try {
    await storage.put('food/2026/08/meal.jpg', Buffer.from('JPEG'));
    assert.ok(fs.existsSync(path.join(dir, 'food', '2026', '08', 'meal.jpg')));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('exists distinguishes present from absent', async () => {
  const { dir, storage } = tmpStorage();
  try {
    await storage.put('a.txt', Buffer.from('x'));
    assert.equal(await storage.exists('a.txt'), true);
    assert.equal(await storage.exists('b.txt'), false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('delete removes the file and is safe to repeat', async () => {
  const { dir, storage } = tmpStorage();
  try {
    await storage.put('gone.txt', Buffer.from('x'));
    await storage.delete('gone.txt');
    assert.equal(await storage.exists('gone.txt'), false);
    await storage.delete('gone.txt');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('a write interrupted after the bytes land but before it reaches the key leaves nothing readable there', async () => {
  const { dir, storage } = tmpStorage();
  const fsp = require('node:fs/promises');
  const originalRename = fsp.rename;
  fsp.rename = async () => {
    throw new Error('simulated crash between write and rename');
  };
  try {
    await assert.rejects(
      () => storage.put('exercises/0001/animation.gif', Buffer.from('GIF89a')),
      /simulated crash between write and rename/,
    );
    assert.equal(await storage.exists('exercises/0001/animation.gif'), false);
    // No temp file left behind either — a resumed run must see a clean directory.
    assert.deepEqual(fs.readdirSync(path.join(dir, 'exercises', '0001')), []);
  } finally {
    fsp.rename = originalRename;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('rejects path traversal keys', async () => {
  const { dir, storage } = tmpStorage();
  try {
    await assert.rejects(() => storage.put('../escaped.txt', Buffer.from('x')), /Invalid storage key/);
    await assert.rejects(() => storage.get('../../etc/passwd'), /Invalid storage key/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('rejects an empty-string key instead of resolving to the storage root', async () => {
  const { dir, storage } = tmpStorage();
  try {
    await assert.rejects(() => storage.put('', Buffer.from('x')), /Invalid storage key/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("rejects a '.' key instead of resolving to the storage root", async () => {
  const { dir, storage } = tmpStorage();
  try {
    await assert.rejects(() => storage.put('.', Buffer.from('x')), /Invalid storage key/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('url returns a servable path', () => {
  const { dir, storage } = tmpStorage();
  try {
    assert.equal(storage.url('exercises/squat.gif'), '/storage/exercises/squat.gif');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('an unsupported mode is rejected', () => {
  assert.throws(() => createStorage({ mode: 's3' }), /s3/);
});
