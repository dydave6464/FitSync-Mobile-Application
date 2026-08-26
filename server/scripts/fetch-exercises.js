'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { load } = require('../src/config');
const { createStorage } = require('../src/services/storage');
const { normalizeRecord, isGif, isJpeg } = require('../src/db/seeds/normalize');

const REPO = 'hasaneyldrm/exercises-dataset';
// Pinned. Tracking main would make re-runs non-reproducible and leave the
// catalogue at the mercy of an upstream force-push.
const COMMIT = '7455efae41b330c265e7cd4b78dfa848e7ce5ebd';
const RAW = `https://raw.githubusercontent.com/${REPO}/${COMMIT}`;

const CONCURRENCY = 8;
const RETRIES = 3;
const TIMEOUT_MS = 30000;
const MANIFEST = path.join(__dirname, '..', 'src', 'db', 'seeds', 'exercises.json');

// The only two shapes a media path takes in the dataset: one directory, one
// filename. Checked before interpolation because URL normalisation collapses
// `..` — a crafted path would otherwise walk out of the pinned-commit prefix
// and pull bytes from a mutable branch, which is the exact thing the pin
// exists to prevent. The leading character must be alphanumeric, so a
// dot-segment cannot pass as a filename either.
const ASSET_PATH = /^(?:videos|images)\/[A-Za-z0-9][A-Za-z0-9._-]*$/;

function assetUrl(sourcePath) {
  if (typeof sourcePath !== 'string' || !ASSET_PATH.test(sourcePath) || sourcePath.includes('..')) {
    throw new Error(`Refusing dataset path outside the pinned tree: ${sourcePath}`);
  }
  return `${RAW}/${sourcePath}`;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// `fetch` and `storage` arrive as dependencies rather than being reached for
// on the global / built inside, so the whole pipeline is testable without a
// network. Same shape as src/services/ml/http-client.js.
async function download(deps, url, attempt = 1) {
  try {
    const response = await deps.fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!response.ok) throw new Error(`${url} responded ${response.status}`);
    return Buffer.from(await response.arrayBuffer());
  } catch (err) {
    if (attempt >= RETRIES) throw err;
    // Injectable only so a test can exercise the retry loop without sitting
    // out the real backoff; the CLI always gets the real one.
    await (deps.sleep || sleep)(2 ** attempt * 500);
    return download(deps, url, attempt + 1);
  }
}

// A fixed pool of workers pulling from a shared cursor. 2,649 sequential
// requests would take about an hour; unbounded parallelism earns a rate-limit.
async function mapWithConcurrency(items, limit, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    for (;;) {
      const index = cursor;
      cursor += 1;
      if (index >= items.length) return;
      results[index] = await worker(items[index], index);
    }
  });
  await Promise.all(runners);
  return results;
}

async function fetchOne(deps, record) {
  const normalized = normalizeRecord(record);
  const failures = [];

  const assets = [
    ['animation_url', record.gif_url, normalized.animation_url, isGif, 'image/gif'],
    ['thumbnail_url', record.image, normalized.thumbnail_url, isJpeg, 'image/jpeg'],
  ];

  for (const [field, sourcePath, key, isValid, contentType] of assets) {
    if (await deps.storage.exists(key)) continue;
    try {
      const buffer = await download(deps, assetUrl(sourcePath));
      // Validate before writing: a rate-limit page is a 200 with bytes in it.
      if (!isValid(buffer)) throw new Error(`${sourcePath} is not valid ${contentType}`);
      await deps.storage.put(key, buffer, contentType);
    } catch (err) {
      normalized[field] = null;
      failures.push({ source_id: record.id, field, reason: err.message });
    }
  }

  return { normalized, failures };
}

async function buildManifest(deps) {
  const log = deps.log || (() => {});

  log(`Fetching dataset at ${COMMIT.slice(0, 8)}...\n`);
  const dataset = JSON.parse((await download(deps, `${RAW}/data/exercises.json`)).toString('utf8'));
  log(`${dataset.length} exercises. Downloading media...\n`);

  let done = 0;
  const results = await mapWithConcurrency(dataset, CONCURRENCY, async (record) => {
    const result = await fetchOne(deps, record);
    done += 1;
    if (done % 100 === 0) log(`  ${done}/${dataset.length}\n`);
    return result;
  });

  return {
    source: { repo: REPO, commit: COMMIT, exercise_count: dataset.length },
    failures: results.flatMap((r) => r.failures),
    exercises: results.map((r) => r.normalized),
  };
}

// Returns the exit code instead of calling process.exit itself, so the
// failure path is reachable from a test. The CLI below exits only on a
// non-zero return; the success path still ends the process naturally.
async function main(overrides = {}) {
  const deps = {
    fetch: overrides.fetch || globalThis.fetch,
    storage: overrides.storage || createStorage(load().storage),
    sleep: overrides.sleep,
    log: overrides.log || ((text) => process.stdout.write(text)),
  };
  const logError = overrides.logError || ((text) => process.stderr.write(text));
  const manifestPath = overrides.manifestPath || MANIFEST;

  const manifest = await buildManifest(deps);

  await fs.mkdir(path.dirname(manifestPath), { recursive: true });
  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const promoted = manifest.exercises.filter((e) => e.promote).length;
  deps.log(
    `Wrote ${manifest.exercises.length} exercises `
      + `(${promoted} live, ${manifest.exercises.length - promoted} pending), `
      + `${manifest.failures.length} asset failures.\n`,
  );

  // Non-zero on any failure so a partial fetch cannot pass unnoticed.
  if (manifest.failures.length > 0) {
    for (const failure of manifest.failures.slice(0, 20)) {
      logError(`  ${failure.source_id} ${failure.field}: ${failure.reason}\n`);
    }
    return 1;
  }

  return 0;
}

if (require.main === module) {
  main()
    .then((code) => {
      if (code !== 0) process.exit(code);
    })
    .catch((err) => {
      console.error(err.message);
      process.exit(1);
    });
}

module.exports = {
  REPO,
  COMMIT,
  RAW,
  CONCURRENCY,
  RETRIES,
  MANIFEST,
  assetUrl,
  download,
  mapWithConcurrency,
  fetchOne,
  buildManifest,
  main,
};
