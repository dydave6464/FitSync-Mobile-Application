'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {
  RAW,
  COMMIT,
  REPO,
  RETRIES,
  assetUrl,
  download,
  mapWithConcurrency,
  fetchOne,
  buildManifest,
  main,
} = require('../scripts/fetch-exercises');

// --- fixtures -------------------------------------------------------------

// Shaped exactly like a record in the dataset's data/exercises.json.
const SIT_UP = {
  id: '0001',
  name: '3/4 sit-up',
  category: 'waist',
  body_part: 'waist',
  equipment: 'body weight',
  target: 'abs',
  muscle_group: 'hip flexors',
  gif_url: 'videos/0001-2gPfomN.gif',
  image: 'images/0001-2gPfomN.jpg',
  instruction_steps: { en: ['Lie flat on your back.', 'Curl forward.'], tr: ['Yat.'] },
};

// The other side of the promotion rule: cardio body part *and* niche equipment.
const BIKE_RUN = {
  id: '0002',
  name: 'stationary bike run v.3',
  category: 'cardio',
  body_part: 'cardio',
  equipment: 'stationary bike',
  target: 'cardiovascular system',
  muscle_group: 'quads',
  gif_url: 'videos/0002-qWyMzQr.gif',
  image: 'images/0002-qWyMzQr.jpg',
  instruction_steps: { en: ['Sit on the bike.'] },
};

const GIF = Buffer.concat([Buffer.from('GIF89a', 'ascii'), Buffer.from([0x10, 0x00, 0x10, 0x00])]);
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);
const HTML = Buffer.from('<!DOCTYPE html><html><body>429 rate limited</body></html>', 'ascii');
const TRUNCATED = Buffer.from('GIF', 'ascii');

// --- doubles --------------------------------------------------------------

function okResponse(buffer) {
  return {
    ok: true,
    status: 200,
    arrayBuffer: async () => Uint8Array.from(buffer).buffer,
  };
}

// Serves media by extension unless `overrides` names a specific URL suffix.
function fakeFetch(handler) {
  const calls = [];
  const impl = async (url, options) => {
    calls.push(String(url));
    return handler(String(url), options);
  };
  impl.calls = calls;
  return impl;
}

function serveMedia(dataset) {
  return fakeFetch(async (url) => {
    if (url.endsWith('/data/exercises.json')) return okResponse(Buffer.from(JSON.stringify(dataset)));
    if (url.endsWith('.gif')) return okResponse(GIF);
    if (url.endsWith('.jpg')) return okResponse(JPEG);
    throw new Error(`unexpected request ${url}`);
  });
}

function fakeStorage(present = []) {
  const files = new Map(present.map((key) => [key, Buffer.from('already here')]));
  const puts = [];
  return {
    files,
    puts,
    async exists(key) {
      return files.has(key);
    },
    async put(key, buffer, contentType) {
      files.set(key, buffer);
      puts.push({ key, buffer, contentType });
      return key;
    },
  };
}

// Every test drives the pipeline through injected dependencies: no global
// fetch is touched, and the real backoff is replaced so the retry loop can be
// exercised without waiting out 1.5s per asset.
function deps(fetchImpl, storage) {
  return { fetch: fetchImpl, storage, sleep: async () => {} };
}

// --- spec §10: the five named cases ---------------------------------------

test('a dataset record becomes a manifest record through the fetch path', async () => {
  const fetchImpl = serveMedia([SIT_UP]);
  const storage = fakeStorage();

  const { normalized, failures } = await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.deepEqual(failures, []);
  assert.deepEqual(normalized, {
    source_id: '0001',
    name: '3/4 sit-up',
    muscle_group: 'abs',
    equipment: 'body weight',
    animation_url: 'exercises/0001/animation.gif',
    thumbnail_url: 'exercises/0001/thumb.jpg',
    promote: true,
    cues: ['Lie flat on your back.', 'Curl forward.'],
  });
});

test('the manifest records the pin and both sides of the promotion rule', async () => {
  const dataset = [SIT_UP, BIKE_RUN];
  const fetchImpl = serveMedia(dataset);

  const manifest = await buildManifest(deps(fetchImpl, fakeStorage()));

  assert.deepEqual(manifest.source, { repo: REPO, commit: COMMIT, exercise_count: 2 });
  assert.deepEqual(manifest.failures, []);
  assert.deepEqual(
    manifest.exercises.map((e) => [e.source_id, e.promote]),
    [['0001', true], ['0002', false]],
  );
  // The dataset JSON is pulled from the pinned commit, not from a branch.
  assert.equal(fetchImpl.calls[0], `${RAW}/data/exercises.json`);
});

test('media is stored under keys derived from source_id, not the upstream filename', async () => {
  const fetchImpl = serveMedia([SIT_UP]);
  const storage = fakeStorage();

  await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.deepEqual(storage.puts.map((p) => p.key), [
    'exercises/0001/animation.gif',
    'exercises/0001/thumb.jpg',
  ]);
  assert.deepEqual(storage.puts.map((p) => p.contentType), ['image/gif', 'image/jpeg']);
  assert.deepEqual(storage.puts[0].buffer, GIF);
  assert.deepEqual(storage.puts[1].buffer, JPEG);
  // The upstream filename is only ever used to build the request URL.
  assert.deepEqual(fetchImpl.calls, [
    `${RAW}/videos/0001-2gPfomN.gif`,
    `${RAW}/images/0001-2gPfomN.jpg`,
  ]);
});

test('a valid GIF passes magic-byte validation and reaches storage', async () => {
  const storage = fakeStorage();
  const fetchImpl = fakeFetch(async (url) => okResponse(url.endsWith('.gif') ? GIF : JPEG));

  const { normalized, failures } = await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.deepEqual(failures, []);
  assert.equal(normalized.animation_url, 'exercises/0001/animation.gif');
  assert.deepEqual(storage.files.get('exercises/0001/animation.gif'), GIF);
});

test('a truncated GIF is rejected and never written to storage', async () => {
  const storage = fakeStorage();
  const fetchImpl = fakeFetch(async (url) => okResponse(url.endsWith('.gif') ? TRUNCATED : JPEG));

  const { normalized, failures } = await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.equal(storage.files.has('exercises/0001/animation.gif'), false);
  assert.equal(normalized.animation_url, null);
  assert.equal(failures.length, 1);
  assert.deepEqual(
    { source_id: failures[0].source_id, field: failures[0].field },
    { source_id: '0001', field: 'animation_url' },
  );
  assert.match(failures[0].reason, /not valid image\/gif/);
  // The thumbnail was fine, so it is kept: one bad asset does not void the row.
  assert.equal(normalized.thumbnail_url, 'exercises/0001/thumb.jpg');
});

test('an HTML error page served as a 200 is rejected and never written to storage', async () => {
  const storage = fakeStorage();
  const fetchImpl = fakeFetch(async () => okResponse(HTML));

  const { normalized, failures } = await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.deepEqual(storage.puts, [], 'nothing should reach storage');
  assert.equal(normalized.animation_url, null);
  assert.equal(normalized.thumbnail_url, null);
  assert.deepEqual(failures.map((f) => f.field), ['animation_url', 'thumbnail_url']);
});

test('an asset already in storage is not re-downloaded', async () => {
  const storage = fakeStorage(['exercises/0001/animation.gif', 'exercises/0001/thumb.jpg']);
  const fetchImpl = fakeFetch(async (url) => {
    throw new Error(`resume must not request ${url}`);
  });

  const { normalized, failures } = await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.deepEqual(fetchImpl.calls, [], 'no request should be made for an asset already present');
  assert.deepEqual(storage.puts, [], 'an existing asset must not be rewritten');
  assert.deepEqual(failures, []);
  assert.equal(normalized.animation_url, 'exercises/0001/animation.gif');
  assert.equal(normalized.thumbnail_url, 'exercises/0001/thumb.jpg');
});

test('an interrupted run resumes: only the missing asset is fetched', async () => {
  const storage = fakeStorage(['exercises/0001/animation.gif']);
  const fetchImpl = serveMedia([SIT_UP]);

  const { failures } = await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.deepEqual(fetchImpl.calls, [`${RAW}/images/0001-2gPfomN.jpg`]);
  assert.deepEqual(storage.puts.map((p) => p.key), ['exercises/0001/thumb.jpg']);
  assert.deepEqual(failures, []);
});

// --- retry, failure recording and the non-zero exit ------------------------

test('a transient failure is retried and the asset still lands', async () => {
  const storage = fakeStorage();
  let gifAttempts = 0;
  const fetchImpl = fakeFetch(async (url) => {
    if (!url.endsWith('.gif')) return okResponse(JPEG);
    gifAttempts += 1;
    if (gifAttempts < RETRIES) return { ok: false, status: 503, arrayBuffer: async () => null };
    return okResponse(GIF);
  });

  const { normalized, failures } = await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.equal(gifAttempts, RETRIES);
  assert.deepEqual(failures, []);
  assert.equal(normalized.animation_url, 'exercises/0001/animation.gif');
});

test('a download that fails every attempt nulls the field instead of aborting the run', async () => {
  const storage = fakeStorage();
  const fetchImpl = fakeFetch(async (url) => {
    if (url.endsWith('.gif')) throw new TypeError('fetch failed');
    return okResponse(JPEG);
  });

  const { normalized, failures } = await fetchOne(deps(fetchImpl, storage), SIT_UP);

  assert.equal(fetchImpl.calls.filter((u) => u.endsWith('.gif')).length, RETRIES);
  assert.equal(normalized.animation_url, null, 'a failed asset must not leave a dangling key');
  assert.equal(normalized.thumbnail_url, 'exercises/0001/thumb.jpg');
  assert.deepEqual(failures, [
    { source_id: '0001', field: 'animation_url', reason: 'fetch failed' },
  ]);
});

test('download gives up after RETRIES attempts and rethrows the last error', async () => {
  let attempts = 0;
  const fetchImpl = fakeFetch(async () => {
    attempts += 1;
    throw new Error(`attempt ${attempts}`);
  });

  await assert.rejects(
    () => download({ fetch: fetchImpl, sleep: async () => {} }, `${RAW}/videos/x.gif`),
    /attempt 3/,
  );
  assert.equal(attempts, RETRIES);
});

test('a failed asset is recorded in the manifest and main exits non-zero', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fitsync-manifest-'));
  const manifestPath = path.join(dir, 'seeds', 'exercises.json');
  try {
    const storage = fakeStorage();
    const fetchImpl = fakeFetch(async (url) => {
      if (url.endsWith('/data/exercises.json')) {
        return okResponse(Buffer.from(JSON.stringify([SIT_UP, BIKE_RUN])));
      }
      if (url.endsWith('0002-qWyMzQr.gif')) return okResponse(HTML);
      return okResponse(url.endsWith('.gif') ? GIF : JPEG);
    });

    const errors = [];
    const code = await main({
      fetch: fetchImpl,
      storage,
      sleep: async () => {},
      log: () => {},
      logError: (text) => errors.push(text),
      manifestPath,
    });

    assert.equal(code, 1, 'a partial fetch must not exit 0');
    assert.equal(errors.length, 1);
    assert.match(errors[0], /0002 animation_url/);

    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    assert.equal(manifest.source.commit, COMMIT);
    assert.deepEqual(manifest.failures.map((f) => [f.source_id, f.field]), [
      ['0002', 'animation_url'],
    ]);
    assert.equal(manifest.exercises[1].animation_url, null);
    assert.equal(manifest.exercises[0].animation_url, 'exercises/0001/animation.gif');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('a clean run writes the manifest and exits zero', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fitsync-manifest-'));
  const manifestPath = path.join(dir, 'seeds', 'exercises.json');
  try {
    const code = await main({
      fetch: serveMedia([SIT_UP, BIKE_RUN]),
      storage: fakeStorage(),
      sleep: async () => {},
      log: () => {},
      logError: () => assert.fail('a clean run must not write to stderr'),
      manifestPath,
    });

    assert.equal(code, 0);
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    assert.equal(manifest.exercises.length, 2);
    assert.deepEqual(manifest.failures, []);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

// --- the worker pool ------------------------------------------------------

test('mapWithConcurrency preserves input order and never exceeds the cap', async () => {
  const items = Array.from({ length: 20 }, (_, i) => i);
  let active = 0;
  let peak = 0;

  const out = await mapWithConcurrency(items, 8, async (item) => {
    active += 1;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setImmediate(resolve));
    active -= 1;
    return item * 2;
  });

  assert.deepEqual(out, items.map((i) => i * 2));
  assert.equal(peak, 8, 'the pool should saturate at the cap');
  assert.equal(active, 0);
});

test('mapWithConcurrency processes every item when there are fewer than the cap', async () => {
  const seen = [];
  const out = await mapWithConcurrency(['a', 'b'], 8, async (item) => {
    seen.push(item);
    return item.toUpperCase();
  });
  assert.deepEqual(seen, ['a', 'b']);
  assert.deepEqual(out, ['A', 'B']);
});

// --- dataset-supplied path validation -------------------------------------

test('a well-formed dataset path resolves against the pinned commit', () => {
  assert.equal(assetUrl('videos/0001-2gPfomN.gif'), `${RAW}/videos/0001-2gPfomN.gif`);
  assert.equal(assetUrl('images/0001-2gPfomN.jpg'), `${RAW}/images/0001-2gPfomN.jpg`);
  assert.ok(assetUrl('videos/0001-2gPfomN.gif').startsWith(`${RAW}/`));
});

test('a dataset path that could escape the pinned commit is refused', () => {
  const refused = [
    'videos/../../../other/repo/main/videos/x.gif',
    '../main/videos/x.gif',
    'videos/..',
    'videos/./x.gif',
    'videos/sub/x.gif',
    'videos/',
    '/videos/x.gif',
    'https://example.invalid/x.gif',
    'scripts/x.gif',
    'videos/x.gif?ref=main',
    undefined,
    null,
  ];
  for (const bad of refused) {
    assert.throws(() => assetUrl(bad), /Refusing dataset path/, `should refuse ${bad}`);
  }
});

test('a crafted media path is recorded as a failure and never requested', async () => {
  const storage = fakeStorage();
  const fetchImpl = fakeFetch(async (url) => {
    if (url.endsWith('.jpg')) return okResponse(JPEG);
    throw new Error(`must not request ${url}`);
  });
  const crafted = { ...SIT_UP, gif_url: '../../refs/heads/main/videos/0001-2gPfomN.gif' };

  const { normalized, failures } = await fetchOne(deps(fetchImpl, storage), crafted);

  assert.deepEqual(fetchImpl.calls, [`${RAW}/images/0001-2gPfomN.jpg`], 'only the safe path is fetched');
  assert.equal(normalized.animation_url, null);
  assert.equal(failures.length, 1);
  assert.match(failures[0].reason, /Refusing dataset path/);
});
