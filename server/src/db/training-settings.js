'use strict';

/// Returned for an account with no row: the table's own default.
const DEFAULTS = Object.freeze({ restSeconds: 90 });

async function readTrainingSettings(pool, userId) {
  const [rows] = await pool.query(
    'SELECT rest_seconds FROM training_settings WHERE user_id = ?', [userId],
  );
  return rows.length ? { restSeconds: Number(rows[0].rest_seconds) } : { ...DEFAULTS };
}

/// Writes [fields] (already validated) and returns the full settings. The
/// first write creates the row.
async function updateTrainingSettings(pool, userId, fields) {
  if (fields.restSeconds !== undefined) {
    await pool.query(
      `INSERT INTO training_settings (user_id, rest_seconds) VALUES (?, ?)
       ON DUPLICATE KEY UPDATE rest_seconds = VALUES(rest_seconds)`,
      [userId, fields.restSeconds],
    );
  }
  return readTrainingSettings(pool, userId);
}

module.exports = { readTrainingSettings, updateTrainingSettings, DEFAULTS };
