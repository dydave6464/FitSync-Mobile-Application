'use strict';

/// The cached cues for one exercise and one injury, in the order they were
/// written. Empty when the pair has never been generated.
async function readPair(pool, exerciseId, injuryId) {
  const [rows] = await pool.query(
    `SELECT title, detail FROM exercise_ai_cues
      WHERE exercise_id = ? AND injury_id = ?
      ORDER BY order_no ASC`,
    [exerciseId, injuryId],
  );
  return rows.map((row) => ({ title: row.title, detail: row.detail }));
}

/// Stores a generated set for a pair.
///
/// Idempotent on uq_eac: a writer that raced past the single-flight lock
/// overwrites the pair rather than doubling its rows. That matters more than
/// usual here because the table has no expiry -- duplicated rows would be
/// rendered as duplicated cues for as long as the exercise exists.
async function writePair(pool, exerciseId, injuryId, cues, model) {
  if (cues.length === 0) return;

  // MySQL 8.0.46: the row-alias form. VALUES() is deprecated since 8.0.20.
  await pool.query(
    `INSERT INTO exercise_ai_cues
       (exercise_id, injury_id, order_no, title, detail, model)
     VALUES ${cues.map(() => '(?, ?, ?, ?, ?, ?)').join(', ')} AS new
     ON DUPLICATE KEY UPDATE
       title = new.title, detail = new.detail, model = new.model`,
    cues.flatMap((cue, index) => [
      exerciseId, injuryId, index + 1, cue.title, cue.detail, model,
    ]),
  );
}

/// The exercise's own seeded cues, shaped like generated ones.
///
/// `detail` is null rather than absent so the client renders one shape either
/// way -- the numbered cards work with or without a second line.
async function catalogueCues(pool, exerciseId) {
  const [rows] = await pool.query(
    'SELECT cue_text FROM coaching_cues WHERE exercise_id = ? ORDER BY order_no ASC',
    [exerciseId],
  );
  return rows.map((row) => ({ title: row.cue_text, detail: null }));
}

module.exports = { readPair, writePair, catalogueCues };
