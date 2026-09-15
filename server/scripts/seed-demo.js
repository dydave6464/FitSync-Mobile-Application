'use strict';
const { load } = require('../src/config');
const { createPool } = require('../src/db/pool');
const { hashPassword } = require('../src/lib/passwords');
const { INJURY_MUSCLE_GROUPS } = require('../src/db/injury-muscle-groups');

// Hardcoded deliberately, and only because of what it is: a self-evidently
// disposable demo credential, so publishing it in a public repository reveals
// nothing. DEMO_PASSWORD overrides it. The reasoning would flip immediately for
// a password used anywhere real.
//
// Note it is seven characters and MIN_PASSWORD_LENGTH (src/routes/auth.js) is
// eight. Nothing breaks -- this writes the hash directly, login never re-checks
// length, and the client has no validator of its own -- but the app itself
// would refuse to ISSUE this password. Use DEMO_PASSWORD=test1234 if that is
// awkward to explain.
const DEFAULT_PASSWORD = 'test123';

// Two accounts, and two regions rather than one, so the injury handling cannot
// look hard-coded to a single case. One injury each: the point is to show which
// injury a decision was made for, and a pile of them makes that unreadable.
const DEMO = {
  'test30@gmail.com': { fullName: 'Test Thirty', injury: 'Shoulder' },
  'test31@gmail.com': { fullName: 'Test ThirtyOne', injury: 'Knee' },
};

// The muscle group each demo injury must actually meet for the account to
// demonstrate anything. Both are in INJURY_MUSCLE_GROUPS for their region --
// 'delts' under upper_body, 'quads' under lower_body -- which is what makes
// these accounts a demonstration rather than a coincidence.
const DEMO_MUSCLE = { Shoulder: 'delts', Knee: 'quads' };

const PLAN_SIZE = 4;

async function seedDemo(pool, { password = DEFAULT_PASSWORD } = {}) {
  const hash = await hashPassword(password);
  const summary = { created: 0, existing: 0 };

  for (const [email, demo] of Object.entries(DEMO)) {
    const [existing] = await pool.query(
      'SELECT user_id FROM users WHERE email = ?', [email],
    );

    let userId;
    if (existing.length > 0) {
      userId = existing[0].user_id;
      summary.existing += 1;
    } else {
      // email_verified = 1 at creation: verification is a hard gate, so a
      // seeded account that skipped it could never sign in.
      const [result] = await pool.query(
        `INSERT INTO users
           (email, password_hash, full_name, sex, date_of_birth, main_goal,
            fitness_level, email_verified, onboarding_completed_at)
         VALUES (?, ?, ?, 'prefer_not_to_say', '2000-01-01', 'build_muscle',
                 'intermediate', 1, NOW())`,
        [email, hash, demo.fullName],
      );
      userId = result.insertId;
      summary.created += 1;
    }

    const regionGroup = await addInjury(pool, userId, demo.injury);
    const planId = await addPlan(pool, userId, demo.injury, regionGroup);
    await addHistory(pool, userId, planId);
  }

  return summary;
}

/// Returns the injury's region_group, which decides what the plan must contain.
async function addInjury(pool, userId, name) {
  const [rows] = await pool.query(
    'SELECT injury_id, region_group FROM injuries WHERE name = ?', [name],
  );
  if (rows.length === 0) {
    throw new Error(
      `Injury "${name}" is not seeded -- run \`npm run seed:injuries\` first`,
    );
  }
  // uq_user_injury makes this idempotent without a pre-read.
  await pool.query(
    'INSERT IGNORE INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
    [userId, rows[0].injury_id],
  );
  return rows[0].region_group;
}

/// An active plan that loads the reported injury, and also does not.
///
/// Hand-built rather than generated: the generator EXCLUDES contraindicated
/// exercises and relaxes its muscle filter unpredictably, so a generated plan
/// cannot be relied on to contain something worth demonstrating. A demo that
/// only works when the generator happens to cooperate is not a demo.
///
/// Both halves matter. One exercise must load the injured region, or there is
/// nothing to show; the rest must not, or there is nothing to compare it
/// against.
async function addPlan(pool, userId, injury, regionGroup) {
  const [existing] = await pool.query(
    'SELECT plan_id FROM workout_plans WHERE user_id = ? AND is_active = TRUE',
    [userId],
  );
  if (existing.length > 0) return existing[0].plan_id;

  const wanted = DEMO_MUSCLE[injury];
  const [targeted] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE status = 'live' AND muscle_group = ? LIMIT 1",
    [wanted],
  );
  if (targeted.length === 0) {
    throw new Error(
      `No live exercise trains "${wanted}" -- run \`npm run seed\` first`,
    );
  }

  const spared = INJURY_MUSCLE_GROUPS[regionGroup] || [];
  const [filler] = await pool.query(
    `SELECT exercise_id FROM exercises
      WHERE status = 'live' AND muscle_group NOT IN (?) LIMIT ?`,
    [spared.length > 0 ? spared : [''], PLAN_SIZE - 1],
  );
  if (filler.length === 0) {
    throw new Error(
      `No live exercise avoids the ${regionGroup} region -- run \`npm run seed\` first`,
    );
  }

  const [plan] = await pool.query(
    `INSERT INTO workout_plans
       (user_id, name, split_style, days_per_week, session_length_min)
     VALUES (?, 'Demo week 1', 'full_body', 3, 45)`,
    [userId],
  );

  const chosen = [targeted[0], ...filler];
  for (const [index, row] of chosen.entries()) {
    await pool.query(
      `INSERT INTO plan_exercises
         (plan_id, exercise_id, order_no, target_sets, target_reps)
       VALUES (?, ?, ?, 3, '8-12')`,
      [plan.insertId, row.exercise_id, index + 1],
    );
  }
  return plan.insertId;
}

/// Two finished sessions, so Progress, the last-performance prefill and
/// repeat-last-workout all have something to show on a fresh account.
async function addHistory(pool, userId, planId) {
  const [existing] = await pool.query(
    'SELECT session_id FROM workout_sessions WHERE user_id = ?', [userId],
  );
  if (existing.length > 0) return;

  const [exercises] = await pool.query(
    'SELECT exercise_id FROM plan_exercises WHERE plan_id = ? ORDER BY order_no',
    [planId],
  );

  // The older session is lighter, so the logger's progressive-overload nudge
  // and the "last 22.5 kg" prefill both have a direction to point in.
  // [how many weeks in, how many days ago]
  const sessions = [[0, 10], [1, 3]];
  for (const [week, daysAgo] of sessions) {
    const [session] = await pool.query(
      `INSERT INTO workout_sessions
         (user_id, plan_id, session_date, status, started_at, duration_min)
       VALUES (?, ?, DATE_SUB(CURDATE(), INTERVAL ? DAY), 'completed',
               DATE_SUB(NOW(), INTERVAL ? DAY), 45)`,
      [userId, planId, daysAgo, daysAgo],
    );
    for (const row of exercises) {
      for (let setNumber = 1; setNumber <= 3; setNumber += 1) {
        await pool.query(
          `INSERT INTO set_logs
             (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
           VALUES (?, ?, ?, ?, ?, TRUE)`,
          [session.insertId, row.exercise_id, setNumber, 20 + week * 2.5, 10],
        );
      }
    }
  }
}

async function main() {
  const config = load();
  const pool = createPool(config.db);
  const password = process.env.DEMO_PASSWORD || DEFAULT_PASSWORD;
  try {
    const summary = await seedDemo(pool, { password });
    console.log(
      `demo accounts: ${summary.created} created, ${summary.existing} already present`,
    );
    for (const [email, demo] of Object.entries(DEMO)) {
      console.log(`  ${email} / ${password}  —  ${demo.injury} injury`);
    }
  } finally {
    await pool.end();
  }
}

if (require.main === module) main();

module.exports = { seedDemo, DEMO, DEFAULT_PASSWORD };
