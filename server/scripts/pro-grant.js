'use strict';
const { load } = require('../src/config');
const { createPool } = require('../src/db/pool');
const { setPremium } = require('../src/db/users');
const { proStatus } = require('../src/db/pro');

/// npm run pro:grant -- --user <id> [--off]
/// Grants an account Pro by hand (or, with --off, takes the grant away): how
/// a demo or teacher account gets Pro without paying. A grant never ends.
/// --off removes only the grant; a period bought through PayMongo still
/// makes the account Pro until it ends, and the message says so.
/// Prints only the user id and the new state -- never an email or a name.

/// ['--user', '34', '--off'] -> { userId: 34, on: false }; null when wrong.
function parseArgs(argv) {
  const at = argv.indexOf('--user');
  const userId = at === -1 ? NaN : Number(argv[at + 1]);
  if (!Number.isInteger(userId) || userId <= 0) return null;
  return { userId, on: !argv.includes('--off') };
}

/// What pro:grant prints. [status] is proStatus after the change.
function resultLine(userId, on, status) {
  const line = `User ${userId}: granted Pro ${on ? 'on' : 'off'}`;
  if (!on && status?.source === 'paid') {
    return `${line} (still Pro until ${status.until.slice(0, 10)} from a paid period).`;
  }
  return `${line}.`;
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
      console.log(resultLine(args.userId, args.on, await proStatus(pool, args.userId)));
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

module.exports = { parseArgs, resultLine };
