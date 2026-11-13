'use strict';
const { load } = require('../src/config');
const { createPool } = require('../src/db/pool');
const { createStorage } = require('../src/services/storage');
const { importDishPhotos } = require('../src/db/dish-photos');

const args = process.argv.slice(2);
const at = args.indexOf('--dir');
const dir = at >= 0 ? args[at + 1] : null;
if (!dir || dir.startsWith('--')) {
  console.error('Usage: npm run photos:import -- --dir <folder with manifest.json> [--replace]');
  process.exit(1);
}

const config = load();
const pool = createPool(config.db);
importDishPhotos({
  pool,
  storage: createStorage(config.storage),
  dir,
  replace: args.includes('--replace'),
  log: (line) => console.log(line),
})
  .then((s) => {
    console.log(
      `Dish photos: ${s.imported.length} imported, ${s.skipped.length} skipped (have a photo), `
        + `${s.notFound.length} not found, ${s.bad.length} bad files.`,
    );
    return pool.end().then(() => process.exit(0));
  })
  .catch((err) => {
    console.error(err.message);
    pool.end().finally(() => process.exit(1));
  });
