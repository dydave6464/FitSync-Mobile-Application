'use strict';
const { load } = require('../src/config');
const { createPool } = require('../src/db/pool');
const { setPremium } = require('../src/db/users');

/// npm run pro:grant -- --user <id> [--off]
/// Marks an account Pro (or, with --off, not Pro). Nobody can buy Pro yet
/// (parked §7), so this is how a demo or teacher account gets Snap a meal.
/// Prints only the user id and the new state -- never an email or a name.

/// ['--user', '34', '--off'] -> { userId: 34, on: false }; null when wrong.
function parseArgs(argv) {
  const at = argv.indexOf('--user');
  const userId = at === -1 ? NaN : Number(argv[at + 1]);
  if (!Number.isInteger(userId) || userId <= 0) return null;
  return { userId, on: !argv.includes('--off') };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args) {
    console.error('usage: npm run pro:grant -- --user <id> [--off]');
    process.exit(2);
  }
  const pool = createPool(load().db);
  try {
    if (await setPremium(pool, args.userId, args.on)) {
      console.log(`User ${args.userId}: Pro ${args.on ? 'on' : 'off'}.`);
    } else {
      console.error(`No user ${args.userId}.`);
      process.exitCode = 1;
    }
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = { parseArgs };
