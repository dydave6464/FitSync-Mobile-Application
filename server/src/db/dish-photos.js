'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { imageTypeOf } = require('../lib/image-check');

/// "npm run photos:import" (round 3, spec 2026-11-13, 2.5): puts the private
/// folder's dish photos into storage and links each to its FitSync food by
/// exact name. Never a FatSecret copy; a dish that already has a photo is
/// skipped unless [replace]. Throws, naming the path, only when the folder or
/// its manifest is missing or unreadable; a bad or missing photo file is
/// counted in `bad` and the run goes on.
async function importDishPhotos({ pool, storage, dir, replace = false, log = () => {} }) {
  if (!fs.existsSync(dir)) throw new Error(`No folder at ${dir}`);
  const manifestPath = path.join(dir, 'manifest.json');
  if (!fs.existsSync(manifestPath)) throw new Error(`No manifest at ${manifestPath}`);
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  } catch (err) {
    throw new Error(`Could not read the manifest at ${manifestPath}: ${err.message}`);
  }
  if (!Array.isArray(manifest)) throw new Error(`The manifest at ${manifestPath} is not a list of dishes`);

  const summary = { imported: [], skipped: [], notFound: [], bad: [] };
  for (const entry of manifest) {
    if (!entry || !entry.file) continue;
    const [[food]] = await pool.query(
      `SELECT f.food_id, f.photo_key FROM foods f
        WHERE f.name COLLATE utf8mb4_bin = ?
          AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
        ORDER BY f.food_id LIMIT 1`,
      [entry.dish],
    );
    if (!food) { summary.notFound.push(entry.dish); log(`not found  ${entry.dish}`); continue; }
    if (food.photo_key && !replace) {
      summary.skipped.push(entry.dish);
      log(`skipped    ${entry.dish} (has a photo)`);
      continue;
    }
    let bytes = null;
    try {
      bytes = fs.readFileSync(path.join(dir, entry.file));
    } catch {
      // A missing or unreadable photo is a bad file, not the end of the run.
    }
    const type = bytes && imageTypeOf(bytes);
    if (!type) { summary.bad.push(entry.dish); log(`bad file   ${entry.dish} (${entry.file})`); continue; }
    const key = `foods/${crypto.randomUUID()}.${type.ext}`;
    await storage.put(key, bytes, type.mime);
    await pool.query('UPDATE foods SET photo_key = ? WHERE food_id = ?', [key, food.food_id]);
    // The replaced file goes last, best-effort: a stray file costs less than a
    // dish pointing at nothing.
    if (food.photo_key) await storage.delete(food.photo_key).catch(() => {});
    summary.imported.push(entry.dish);
    log(`imported   ${entry.dish}`);
  }
  return summary;
}

module.exports = { importDishPhotos };
