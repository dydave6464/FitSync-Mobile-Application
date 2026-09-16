'use strict';
const { load } = require('../src/config');
const { createPool } = require('../src/db/pool');
const { createCueService } = require('../src/services/cues');
const { flagFor } = require('../src/db/cue-gate');
const { readPair, writePair } = require('../src/db/ai-cues');

/// Pre-fills the cue cache for one user's active plan.
///
/// This is the lazy runtime path, run ahead of time. It exists so a
/// consultation or a defence never depends on the network: warm the pairs
/// beforehand and every demo screen becomes a MySQL read.
///
/// Idempotent, and deliberately narrow -- it walks the ACTIVE plan only, and
/// within it only the exercises the gate flags. Warming anything else would be
/// buying cues for screens nobody is about to open.
async function warmCues(pool, service, { userId }) {
  const [rows] = await pool.query(
    `SELECT DISTINCT pe.exercise_id, e.name, e.muscle_group
       FROM workout_plans p
       JOIN plan_exercises pe ON pe.plan_id = p.plan_id
       JOIN exercises e ON e.exercise_id = pe.exercise_id
      WHERE p.user_id = ? AND p.is_active = TRUE
      ORDER BY pe.exercise_id`,
    [userId],
  );

  const summary = { filled: 0, skipped: 0, failed: 0 };

  // Sequential on purpose. A burst is exactly what a free-tier rate limit
  // refuses, and this is the one place that would produce one -- a plan's
  // worth of generations, all at once, from a cold cache.
  for (const row of rows) {
    const flag = await flagFor(pool, userId, row.exercise_id);
    if (!flag) continue;

    const cached = await readPair(pool, row.exercise_id, flag.injuryId);
    if (cached.length > 0) {
      summary.skipped += 1;
      continue;
    }

    const cues = await service.generate({
      exerciseName: row.name,
      muscleGroup: row.muscle_group,
      injuryName: flag.injuryName,
      reason: flag.reason,
    });
    // The service returns null for every failure it has; it never throws.
    if (!cues || cues.length === 0) {
      summary.failed += 1;
      continue;
    }

    await writePair(pool, row.exercise_id, flag.injuryId, cues, service.model);
    summary.filled += 1;
  }

  return summary;
}

async function main() {
  const at = process.argv.indexOf('--email');
  if (at === -1 || !process.argv[at + 1]) {
    console.error('usage: node scripts/warm-cues.js --email <address>');
    process.exit(1);
  }
  const email = process.argv[at + 1];

  const config = load();
  const pool = createPool(config.db);
  try {
    const [users] = await pool.query(
      'SELECT user_id FROM users WHERE email = ?', [email],
    );
    if (users.length === 0) {
      console.error(`No user with email ${email}`);
      process.exit(1);
    }

    const service = createCueService(config.cues);
    const summary = await warmCues(pool, service, { userId: users[0].user_id });

    console.log(
      `warmed ${email} via ${service.model}: ${summary.filled} filled, `
        + `${summary.skipped} already cached, ${summary.failed} failed`,
    );
    if (service.model === 'stub') {
      console.log('  CUES_MODE is stub -- these are placeholder cues, not Groq output.');
      console.log('  Re-run with CUES_MODE=groq to fill the cache for real.');
    }
    if (summary.failed > 0) {
      console.log('  failures are usually the free-tier rate limit; re-run in a minute');
    }
  } finally {
    await pool.end();
  }
}

if (require.main === module) main();

module.exports = { warmCues };
