'use strict';
const { createPool } = require('./pool');
const PREFERENCES = require('./seeds/exercise-preferences.json');

// Writes the team's curated marks (priority and beginner_friendly) onto the
// catalogue. The list is keyed by sourceId because exercise_id differs
// between databases; a sourceId this database does not have is skipped.
// Rows with is_manual = 1 are a later hand edit and are never written here
// (the exercise_categories pattern).

const UPSERT = `
  INSERT INTO exercise_preferences (exercise_id, priority, beginner_friendly)
  VALUES (?, ?, ?)
  ON DUPLICATE KEY UPDATE priority = VALUES(priority), beginner_friendly = VALUES(beginner_friendly)
`;

async function seedExercisePreferences(dbConfig) {
  const pool = createPool(dbConfig);
  try {
    const [known] = await pool.query(
      'SELECT exercise_id, source_id FROM exercises WHERE source_id IN (?)',
      [PREFERENCES.map((p) => p.sourceId)],
    );
    const idOf = new Map(known.map((r) => [r.source_id, r.exercise_id]));
    const [current] = await pool.query(
      'SELECT exercise_id, priority, beginner_friendly, is_manual FROM exercise_preferences',
    );
    const existing = new Map(current.map((r) => [r.exercise_id, r]));
    const manual = new Set(current.filter((r) => r.is_manual === 1).map((r) => r.exercise_id));

    let inserted = 0;
    let updated = 0;
    let unchanged = 0;
    let skippedUnknown = 0;
    for (const p of PREFERENCES) {
      const exerciseId = idOf.get(p.sourceId);
      if (exerciseId === undefined) {
        skippedUnknown += 1;
        continue;
      }
      if (manual.has(exerciseId)) continue;
      // Compared here rather than read off affectedRows: under mysql2's
      // CLIENT_FOUND_ROWS an identical upsert and an insert both report 1.
      const row = existing.get(exerciseId);
      if (row && row.priority === p.priority && Boolean(row.beginner_friendly) === p.beginnerFriendly) {
        unchanged += 1;
        continue;
      }
      await pool.query(UPSERT, [exerciseId, p.priority, p.beginnerFriendly]);
      if (row) updated += 1;
      else inserted += 1;
    }
    return {
      inserted, updated, unchanged, skippedUnknown, manual: manual.size, total: PREFERENCES.length,
    };
  } finally {
    await pool.end();
  }
}

// A run where no sourceId matched wrote nothing: most likely the catalogue
// is not seeded yet (`npm run seed` comes first). Every beginner plan needs
// these marks, so that must not pass as a quiet success. Null when fine.
function nothingMatched(summary) {
  if (summary.total === 0 || summary.skippedUnknown !== summary.total) return null;
  return `None of the ${summary.total} exercise preferences matched the catalogue, `
    + 'so nothing was written. Run `npm run seed` first, then '
    + '`npm run seed:preferences` again.';
}

module.exports = { seedExercisePreferences, PREFERENCES, nothingMatched };
