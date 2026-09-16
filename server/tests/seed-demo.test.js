'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { verifyPassword, hashPassword } = require('../src/lib/passwords');
const { loadsRegion } = require('../src/db/injury-muscle-groups');
const { seedDemo } = require('../scripts/seed-demo');

/// A catalogue small enough to reason about, with one exercise for each demo
/// injury's muscle group and three that load nothing either account reported.
async function seedCatalogue(pool) {
  const rows = [
    ['Overhead Press', 'delts'],
    ['Barbell Back Squat', 'quads'],
    ['Seated Calf Raise', 'calves'],
    ['Cable Crunch', 'abs'],
    ['Bench Press', 'pectorals'],
  ];
  for (const [name, muscleGroup] of rows) {
    await pool.query(
      "INSERT INTO exercises (name, muscle_group, status) VALUES (?, ?, 'live')",
      [name, muscleGroup],
    );
  }
}

test('the demo accounts', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());
  await seedCatalogue(pool);

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('creates test30 and test31, and nobody else', async () => {
    await seedDemo(pool, { password: 'test123' });

    const [rows] = await pool.query(
      "SELECT email FROM users WHERE email LIKE 'test3%@gmail.com' ORDER BY email",
    );
    assert.deepEqual(rows.map((r) => r.email),
      ['test30@gmail.com', 'test31@gmail.com']);
  });

  // Verification is a hard gate -- an unverified account cannot sign in -- and
  // an account that lands back in onboarding is not a demo.
  await t.test('both are verified and onboarded', async () => {
    const [rows] = await pool.query(
      `SELECT email_verified, onboarding_completed_at FROM users
        WHERE email LIKE 'test3%@gmail.com'`,
    );
    assert.equal(rows.length, 2);
    for (const row of rows) {
      assert.equal(row.email_verified, 1);
      assert.notEqual(row.onboarding_completed_at, null);
    }
  });

  await t.test('the password actually signs in', async () => {
    const [rows] = await pool.query(
      "SELECT password_hash FROM users WHERE email = 'test30@gmail.com'",
    );
    assert.equal(await verifyPassword('test123', rows[0].password_hash), true);
  });

  await t.test('test30 carries a shoulder and test31 a knee', async () => {
    const [rows] = await pool.query(
      `SELECT u.email, i.name FROM users u
         JOIN user_injuries ui ON ui.user_id = u.user_id
         JOIN injuries i ON i.injury_id = ui.injury_id
        WHERE u.email LIKE 'test3%@gmail.com' ORDER BY u.email`,
    );
    assert.deepEqual(rows.map((r) => [r.email, r.name]), [
      ['test30@gmail.com', 'Shoulder'],
      ['test31@gmail.com', 'Knee'],
    ]);
  });

  // One injury each, not a pile: the point of these accounts is to show which
  // injury a decision was made for, and four injuries makes that unreadable.
  await t.test('exactly one injury each', async () => {
    const [rows] = await pool.query(
      `SELECT u.email, COUNT(*) AS n FROM user_injuries ui
         JOIN users u ON u.user_id = ui.user_id
        WHERE u.email LIKE 'test3%@gmail.com' GROUP BY u.email`,
    );
    assert.equal(rows.length, 2);
    for (const row of rows) assert.equal(Number(row.n), 1);
  });

  // The whole point of the accounts. Asserted against the region map rather
  // than against the seed's own choice of exercise, so this proves the choice
  // is CORRECT and not merely self-consistent.
  await t.test('each active plan contains an exercise that loads the injury',
    async () => {
      const [rows] = await pool.query(
        `SELECT u.email, i.region_group, e.muscle_group
           FROM users u
           JOIN user_injuries ui ON ui.user_id = u.user_id
           JOIN injuries i ON i.injury_id = ui.injury_id
           JOIN workout_plans p ON p.user_id = u.user_id AND p.is_active = TRUE
           JOIN plan_exercises pe ON pe.plan_id = p.plan_id
           JOIN exercises e ON e.exercise_id = pe.exercise_id
          WHERE u.email LIKE 'test3%@gmail.com'`,
      );

      for (const email of ['test30@gmail.com', 'test31@gmail.com']) {
        const mine = rows.filter((r) => r.email === email);
        assert.ok(mine.length > 0, `${email} has no active plan with exercises`);
        assert.ok(
          mine.some((r) => loadsRegion(r.region_group, r.muscle_group)),
          `${email}'s plan contains nothing that loads the reported injury`,
        );
      }
    });

  // The other half of the demonstration: a plan of nothing BUT the injured
  // region would never show what an unflagged exercise looks like.
  await t.test('each plan also contains an exercise that loads nothing injured',
    async () => {
      const [rows] = await pool.query(
        `SELECT u.email, i.region_group, e.muscle_group
           FROM users u
           JOIN user_injuries ui ON ui.user_id = u.user_id
           JOIN injuries i ON i.injury_id = ui.injury_id
           JOIN workout_plans p ON p.user_id = u.user_id AND p.is_active = TRUE
           JOIN plan_exercises pe ON pe.plan_id = p.plan_id
           JOIN exercises e ON e.exercise_id = pe.exercise_id
          WHERE u.email LIKE 'test3%@gmail.com'`,
      );

      for (const email of ['test30@gmail.com', 'test31@gmail.com']) {
        const mine = rows.filter((r) => r.email === email);
        assert.ok(
          mine.some((r) => !loadsRegion(r.region_group, r.muscle_group)),
          `${email}'s plan is entirely injured-region work`,
        );
      }
    });

  await t.test('both have history for Progress and repeat-last-workout',
    async () => {
      const [rows] = await pool.query(
        `SELECT u.email,
                COUNT(DISTINCT ws.session_id) AS sessions,
                COUNT(sl.set_log_id) AS sets
           FROM users u
           JOIN workout_sessions ws
             ON ws.user_id = u.user_id AND ws.status = 'completed'
           LEFT JOIN set_logs sl ON sl.session_id = ws.session_id
          WHERE u.email LIKE 'test3%@gmail.com'
          GROUP BY u.email`,
      );

      assert.equal(rows.length, 2);
      for (const row of rows) {
        // Two recent sessions plus eight backdated ones for the Progress charts.
        assert.equal(Number(row.sessions), 10, `${row.email} needs ten sessions`);
        assert.ok(Number(row.sets) > 0, `${row.email} needs logged sets`);
      }
    });

  await t.test('rerunning creates nobody and nothing twice', async () => {
    const result = await seedDemo(pool, { password: 'test123' });
    assert.equal(result.created, 0);

    const [users] = await pool.query(
      "SELECT COUNT(*) AS n FROM users WHERE email LIKE 'test3%@gmail.com'",
    );
    assert.equal(Number(users[0].n), 2);

    const [plans] = await pool.query(
      `SELECT COUNT(*) AS n FROM workout_plans p
         JOIN users u ON u.user_id = p.user_id
        WHERE u.email LIKE 'test3%@gmail.com'`,
    );
    assert.equal(Number(plans[0].n), 2);

    const [sessions] = await pool.query(
      `SELECT COUNT(*) AS n FROM workout_sessions ws
         JOIN users u ON u.user_id = ws.user_id
        WHERE u.email LIKE 'test3%@gmail.com'`,
    );
    // Ten sessions each (two recent, eight backdated), times two accounts.
    assert.equal(Number(sessions[0].n), 20);
  });

  await t.test('demo accounts have enough history to draw a line', async () => {
    const [[user]] = await pool.query(
      "SELECT user_id FROM users WHERE email = 'test30@gmail.com'",
    );

    const [[sessions]] = await pool.query(
      `SELECT COUNT(*) AS n FROM workout_sessions
        WHERE user_id = ? AND status = 'completed'`,
      [user.user_id],
    );
    assert.ok(Number(sessions.n) >= 8, 'enough sessions for a trend');

    const [[weights]] = await pool.query(
      'SELECT COUNT(*) AS n FROM body_weight_logs WHERE user_id = ?',
      [user.user_id],
    );
    assert.ok(Number(weights.n) >= 6, 'enough weigh-ins for a line');

    // A repeated lift across sessions is what turns the strength chart from a
    // set-axis single session into a date-axis trend.
    const [[repeated]] = await pool.query(
      `SELECT COUNT(DISTINCT s.session_id) AS n
         FROM set_logs sl
         JOIN workout_sessions s ON s.session_id = sl.session_id
        WHERE s.user_id = ? AND sl.weight_kg IS NOT NULL
        GROUP BY sl.exercise_id
        ORDER BY n DESC LIMIT 1`,
      [user.user_id],
    );
    assert.ok(Number(repeated.n) >= 4, 'one lift repeated across sessions');
  });
});

// Found by actually running the seeder against a database that already had a
// demo account with a leftover 'abandoned' session (started, never finished --
// exactly what a person testing the app by hand leaves behind). The old
// existence check ignored status, so that one row alone made addHistory treat
// the account as already having history and skip it, silently leaving the
// account with none of the backdated data the Progress charts need.
test('an abandoned session does not block backdated history', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());
  await seedCatalogue(pool);

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const hash = await hashPassword('test123');
  const [user] = await pool.query(
    `INSERT INTO users
       (email, password_hash, full_name, sex, date_of_birth, main_goal,
        fitness_level, email_verified, onboarding_completed_at)
     VALUES ('test30@gmail.com', ?, 'Test Thirty', 'prefer_not_to_say',
             '2000-01-01', 'build_muscle', 'intermediate', 1, NOW())`,
    [hash],
  );
  // A started-and-abandoned session, exactly like one left behind by someone
  // trying the app -- no plan, no sets, and NOT the history this task adds.
  await pool.query(
    `INSERT INTO workout_sessions (user_id, status, session_date)
     VALUES (?, 'abandoned', CURDATE())`,
    [user.insertId],
  );

  await seedDemo(pool, { password: 'test123' });

  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS n FROM workout_sessions
      WHERE user_id = ? AND status = 'completed'`,
    [user.insertId],
  );
  assert.ok(Number(row.n) >= 8, 'the abandoned session must not suppress history');
});
