'use strict';
const { load } = require('../src/config');
const { createPool } = require('../src/db/pool');
const { hashPassword } = require('../src/lib/passwords');
const { INJURY_MUSCLE_GROUPS } = require('../src/db/injury-muscle-groups');
const { writeEntry } = require('../src/db/body-weight');

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

// Shared with addPlan's `days_per_week` column so the backdated history it
// writes trains at the SAME cadence the plan claims -- one number, used in
// both places, rather than a plan that says 3 and a history that says 1. A
// mismatch there is exactly what made adherence read 5/12 instead of
// something plausible.
const DAYS_PER_WEEK = 3;

// How many weeks of backdated history addHistory writes. Long enough that
// the Month and Year volume windows have more than one bucket of shape;
// short enough that the Year adherence ratio still reads as "a fairly new
// account", which it is.
const HISTORY_WEEKS = 8;

// Day-of-week offsets (days ago, within a single week, oldest to newest) for
// DAYS_PER_WEEK training sessions. Kept in step with DAYS_PER_WEEK -- add an
// offset here if that constant ever grows. All are under 7, so the most
// recent week's sessions land inside the 7-day Week window and that chart is
// never all zero.
const WEEK_OFFSETS = [5, 3, 1];

// Of those, the one day a week that also trains the rest of the plan (an
// accessory / full-body day) and gets that week's weigh-in. Real programs
// don't repeat every exercise every session, and giving the tracked lift
// more sets than the others is also what makes it the one
// `strength.readOptions` ranks first.
const FULL_SESSION_OFFSET = 3;

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
     VALUES (?, 'Demo week 1', 'full_body', ?, 45)`,
    [userId, DAYS_PER_WEEK],
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

/// `HISTORY_WEEKS` weeks of backdated sessions, at `DAYS_PER_WEEK` sessions a
/// week, so Progress, the last-performance prefill and repeat-last-workout
/// all have something to show on a fresh account -- and so every chart on
/// the Progress tab has enough points to draw a line.
///
/// ONE write path. An earlier version of this function had two: two flat
/// "recent" sessions logging all four exercises at a fixed weight, plus a
/// separately-scheduled backdated block progressing just the compound lift.
/// They coexisted on the same account and fought each other -- the flat
/// sessions had no `total_volume_kg`, so the Week chart (whose only session
/// fell on one of them) summed to zero; they also logged the SAME exercise
/// the backdated block was progressing, at a weight lower than where the
/// progression already was, so the e1RM series sawtoothed instead of rising.
/// There is exactly one schedule now, and it is internally consistent by
/// construction.
async function addHistory(pool, userId, planId) {
  // Filtered to 'completed': an abandoned or in-progress session left behind
  // by someone trying the app by hand is not history, and must not make this
  // look already-seeded and skip adding any.
  const [existing] = await pool.query(
    `SELECT session_id FROM workout_sessions
      WHERE user_id = ? AND status = 'completed'`,
    [userId],
  );
  if (existing.length > 0) return;

  const [exercises] = await pool.query(
    'SELECT exercise_id FROM plan_exercises WHERE plan_id = ? ORDER BY order_no',
    [planId],
  );
  // exercises[0] is `targeted[0]` from addPlan: the exercise chosen to load
  // the reported injury. Tracking IT specifically -- rather than an
  // arbitrary plan exercise -- means the strength chart shows the account
  // improving on the exact lift the injury story is about.
  const [compound, ...fillers] = exercises;

  let sessionIndex = 0; // oldest = 0, rises every session -> e1RM never dips
  for (let weeksAgo = HISTORY_WEEKS - 1; weeksAgo >= 0; weeksAgo -= 1) {
    for (const offset of WEEK_OFFSETS) {
      const daysAgo = weeksAgo * 7 + offset;
      // +0.5 kg every session: modest enough to be believable over eight
      // weeks, and strictly increasing so there is no plateau to mistake for
      // a stall, let alone a dip.
      const weight = 60 + sessionIndex * 0.5;
      sessionIndex += 1;

      const [session] = await pool.query(
        `INSERT INTO workout_sessions (user_id, plan_id, status, session_date, duration_min)
         VALUES (?, ?, 'completed', DATE_SUB(CURDATE(), INTERVAL ? DAY), 45)`,
        [userId, planId, daysAgo],
      );

      for (let setNo = 1; setNo <= 3; setNo += 1) {
        await pool.query(
          `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
           VALUES (?, ?, ?, ?, ?, TRUE)`,
          [session.insertId, compound.exercise_id, setNo, weight, 11 - setNo],
        );
      }

      // The full-body day: also trains the rest of the plan, which is what
      // gives "sets by muscle" more than one bar, and rides the week's
      // weigh-in. Fewer sets than the compound lift gets overall (this
      // happens once a week, the compound lift every session), so
      // `strength.readOptions` still ranks the progressing lift first.
      if (offset === FULL_SESSION_OFFSET) {
        for (const filler of fillers) {
          for (let setNo = 1; setNo <= 3; setNo += 1) {
            await pool.query(
              `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
               VALUES (?, ?, ?, 20, 10, TRUE)`,
              [session.insertId, filler.exercise_id, setNo],
            );
          }
        }

        const [[day]] = await pool.query(
          'SELECT DATE_SUB(CURDATE(), INTERVAL ? DAY) AS d', [daysAgo],
        );
        await writeEntry(pool, userId, {
          weightKg: 78 - (HISTORY_WEEKS - 1 - weeksAgo) * 0.4,
          loggedOn: day.d,
        });
      }

      // The exact derivation `completeSession()` uses (src/db/sessions.js),
      // run again here now that every set for this session is in. Matching
      // it -- rather than computing the number in JS and hoping it agrees --
      // is what makes a seeded session indistinguishable in shape from one
      // someone actually logged, and is why this runs AFTER the inserts
      // above rather than being stamped into the INSERT.
      await pool.query(
        `UPDATE workout_sessions
            SET total_volume_kg = (SELECT COALESCE(SUM(weight_kg * reps), 0)
                                      FROM set_logs
                                     WHERE session_id = ? AND is_completed = TRUE)
          WHERE session_id = ?`,
        [session.insertId, session.insertId],
      );
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
