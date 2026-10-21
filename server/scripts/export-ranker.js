'use strict';
const fs = require('node:fs');
const { load } = require('../src/config');
const { createPool } = require('../src/db/pool');
const { exportRankerRows, toCsv } = require('../src/db/ranker-export');

/// npm run export:ranker -- --out <file.csv>
/// Writes real labelled rows for `python -m app.train_ranker --real <file>`.
/// Prints counts only -- never a row, a profile or any configuration.
async function main() {
  const at = process.argv.indexOf('--out');
  const out = at === -1 ? null : process.argv[at + 1];
  if (!out) {
    console.error('usage: npm run export:ranker -- --out <file.csv>');
    process.exit(2);
  }
  const pool = createPool(load().db);
  try {
    const rows = await exportRankerRows(pool);
    fs.writeFileSync(out, toCsv(rows));
    const users = new Set(rows.map((r) => r.user_id)).size;
    const done = rows.filter((r) => r.done === 1).length;
    console.log(`Wrote ${rows.length} rows from ${users} users (${done} done, ${rows.length - done} not) to ${out}.`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
