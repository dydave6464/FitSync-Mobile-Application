'use strict';
const { load } = require('../src/config');
const { createPool } = require('../src/db/pool');
const { createAdminAccount } = require('../src/db/admins');

/// npm run admin:create -- --email <email> --name "<full name>"
/// Creates an admin for the admin dashboard. There is no admin sign-up in the
/// app: this is the only way one is made. The password is asked for twice,
/// hidden, so it never reaches argv or shell history. Refuses an email an
/// admin or a trainee already uses (db/admins.js createAdminAccount).

const USAGE = 'usage: npm run admin:create -- --email <email> --name "<full name>"';

/// ['--email', 'A@X.test', '--name', 'Ada'] -> { email: 'a@x.test', fullName: 'Ada' };
/// null when either is missing.
function parseArgs(argv) {
  const value = (flag) => {
    const at = argv.indexOf(flag);
    return at === -1 || typeof argv[at + 1] !== 'string' ? null : argv[at + 1].trim();
  };
  const email = value('--email');
  const fullName = value('--name');
  if (!email || !fullName) return null;
  return { email: email.toLowerCase(), fullName };
}

/// Reads a line without echoing it (the password never reaches argv or history).
function promptHidden(question) {
  const readline = require('readline');
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    rl._writeToOutput = (s) => { if (s.startsWith(question)) process.stdout.write(s); };
    rl.question(question, (answer) => { rl.close(); process.stdout.write('\n'); resolve(answer); });
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args) {
    console.error(USAGE);
    process.exit(2);
  }
  const password = await promptHidden('Password: ');
  const again = await promptHidden('Password again: ');
  if (password !== again) {
    console.error("Passwords don't match.");
    process.exit(1);
  }
  const pool = createPool(load().db);
  try {
    const { adminId } = await createAdminAccount(pool, { ...args, password });
    console.log(`Admin created: ${args.email} (id ${adminId})`);
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
