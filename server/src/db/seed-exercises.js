'use strict';
const mysql = require('mysql2/promise');

// MySQL 8.0.46: the row-alias form. VALUES() is deprecated since 8.0.20.
const UPSERT_EQUIPMENT = `
  INSERT INTO equipment (name) VALUES (?) AS new
  ON DUPLICATE KEY UPDATE name = new.name
`;

// status is intentionally absent from the update list. An admin who promotes a
// pending exercise must not have that decision reverted by the next re-seed.
const UPSERT_EXERCISE = `
  INSERT INTO exercises
    (source_id, name, muscle_group, equipment_id, animation_url, thumbnail_url, status)
  VALUES (?, ?, ?, ?, ?, ?, ?) AS new
  ON DUPLICATE KEY UPDATE
    name          = new.name,
    muscle_group  = new.muscle_group,
    equipment_id  = new.equipment_id,
    animation_url = new.animation_url,
    thumbnail_url = new.thumbnail_url
`;

async function seedExercises(dbConfig, manifest, { logger = null } = {}) {
  const connection = await mysql.createConnection({
    host: dbConfig.host,
    port: dbConfig.port,
    user: dbConfig.user,
    password: dbConfig.password,
    database: dbConfig.database,
    charset: 'utf8mb4',
  });

  const summary = { equipment: 0, exercises: 0, cues: 0, skipped: 0 };

  try {
    await connection.beginTransaction();

    // Equipment first: exercises.equipment_id is ON DELETE RESTRICT, so the
    // referenced row has to exist before any exercise insert.
    const names = [...new Set(manifest.exercises.map((e) => e.equipment))].sort();
    for (const name of names) {
      await connection.query(UPSERT_EQUIPMENT, [name]);
    }
    summary.equipment = names.length;

    const [equipmentRows] = await connection.query('SELECT equipment_id, name FROM equipment');
    const equipmentIds = new Map(equipmentRows.map((r) => [r.name, r.equipment_id]));

    for (const exercise of manifest.exercises) {
      if (!exercise.animation_url) {
        summary.skipped += 1;
        continue;
      }

      await connection.query(UPSERT_EXERCISE, [
        exercise.source_id,
        exercise.name,
        exercise.muscle_group,
        equipmentIds.get(exercise.equipment) ?? null,
        exercise.animation_url,
        exercise.thumbnail_url,
        exercise.promote ? 'live' : 'pending',
      ]);

      const [[row]] = await connection.query(
        'SELECT exercise_id FROM exercises WHERE source_id = ?',
        [exercise.source_id],
      );

      // Replace rather than append: an upstream edit can shorten the step list,
      // and cues have no natural key to upsert against.
      await connection.query('DELETE FROM coaching_cues WHERE exercise_id = ?', [row.exercise_id]);
      for (const [index, cue] of exercise.cues.entries()) {
        await connection.query(
          'INSERT INTO coaching_cues (exercise_id, order_no, cue_text) VALUES (?, ?, ?)',
          [row.exercise_id, index + 1, cue],
        );
      }

      summary.exercises += 1;
      summary.cues += exercise.cues.length;
    }

    await connection.commit();
    if (logger && logger.info) {
      logger.info(`seeded ${summary.exercises} exercises, ${summary.cues} cues`);
    }
  } catch (err) {
    await connection.rollback();
    throw err;
  } finally {
    await connection.end();
  }

  return summary;
}

module.exports = { seedExercises };
