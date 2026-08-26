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

async function download(url, attempt = 1) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!response.ok) throw new Error(`${url} responded ${response.status}`);
    return Buffer.from(await response.arrayBuffer());
  } catch (err) {
    if (attempt >= RETRIES) throw err;
    await new Promise((resolve) => setTimeout(resolve, 2 ** attempt * 500));
    return download(url, attempt + 1);
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

async function fetchOne(storage, record) {
  const normalized = normalizeRecord(record);
  const failures = [];

  const assets = [
    ['animation_url', record.gif_url, normalized.animation_url, isGif, 'image/gif'],
    ['thumbnail_url', record.image, normalized.thumbnail_url, isJpeg, 'image/jpeg'],
  ];

  for (const [field, sourcePath, key, isValid, contentType] of assets) {
    if (await storage.exists(key)) continue;
    try {
      const buffer = await download(`${RAW}/${sourcePath}`);
      // Validate before writing: a rate-limit page is a 200 with bytes in it.
      if (!isValid(buffer)) throw new Error(`${sourcePath} is not valid ${contentType}`);
      await storage.put(key, buffer, contentType);
    } catch (err) {
      normalized[field] = null;
      failures.push({ source_id: record.id, field, reason: err.message });
    }
  }

  return { normalized, failures };
}

async function main() {
  const storage = createStorage(load().storage);

  process.stdout.write(`Fetching dataset at ${COMMIT.slice(0, 8)}...\n`);
  const dataset = JSON.parse((await download(`${RAW}/data/exercises.json`)).toString('utf8'));
  process.stdout.write(`${dataset.length} exercises. Downloading media...\n`);

  let done = 0;
  const results = await mapWithConcurrency(dataset, CONCURRENCY, async (record) => {
    const result = await fetchOne(storage, record);
    done += 1;
    if (done % 100 === 0) process.stdout.write(`  ${done}/${dataset.length}\n`);
    return result;
  });

  const manifest = {
    source: { repo: REPO, commit: COMMIT, exercise_count: dataset.length },
    failures: results.flatMap((r) => r.failures),
    exercises: results.map((r) => r.normalized),
  };

  await fs.mkdir(path.dirname(MANIFEST), { recursive: true });
  await fs.writeFile(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`);

  const promoted = manifest.exercises.filter((e) => e.promote).length;
  process.stdout.write(
    `Wrote ${manifest.exercises.length} exercises `
      + `(${promoted} live, ${manifest.exercises.length - promoted} pending), `
      + `${manifest.failures.length} asset failures.\n`,
  );

  // Non-zero on any failure so a partial fetch cannot pass unnoticed.
  if (manifest.failures.length > 0) {
    for (const failure of manifest.failures.slice(0, 20)) {
      process.stderr.write(`  ${failure.source_id} ${failure.field}: ${failure.reason}\n`);
    }
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
