'use strict';

/// Returned for an account with no row: the table's own defaults.
const DEFAULTS = Object.freeze({
  habitsEnabled: true,
  habitLeadMin: 15,
  workoutEnabled: false,
  workoutTime: '07:00',
  checkinEnabled: false,
  checkinTime: '07:00',
});

/// camelCase field -> column. The only keys an update may write.
const COLUMNS = {
  habitsEnabled: 'habits_enabled',
  habitLeadMin: 'habit_lead_min',
  workoutEnabled: 'workout_enabled',
  workoutTime: 'workout_time',
  checkinEnabled: 'checkin_enabled',
  checkinTime: 'checkin_time',
};

function toSettings(row) {
  return {
    habitsEnabled: Boolean(row.habits_enabled),
    habitLeadMin: Number(row.habit_lead_min),
    workoutEnabled: Boolean(row.workout_enabled),
    workoutTime: String(row.workout_time).slice(0, 5),
    checkinEnabled: Boolean(row.checkin_enabled),
    checkinTime: String(row.checkin_time).slice(0, 5),
  };
}

async function readReminderSettings(pool, userId) {
  const [rows] = await pool.query(
    'SELECT * FROM reminder_settings WHERE user_id = ?', [userId],
  );
  return rows.length ? toSettings(rows[0]) : { ...DEFAULTS };
}

/// Writes [fields] (already validated, camelCase keys from COLUMNS) and
/// returns the full settings. The first write creates the row; the rest of
/// it takes the column defaults.
async function updateReminderSettings(pool, userId, fields) {
  const keys = Object.keys(fields).filter((k) => Object.hasOwn(COLUMNS, k));
  if (keys.length > 0) {
    const cols = keys.map((k) => COLUMNS[k]);
    const values = keys.map((k) => fields[k]);
    await pool.query(
      `INSERT INTO reminder_settings (user_id, ${cols.join(', ')})
       VALUES (?, ${cols.map(() => '?').join(', ')})
       ON DUPLICATE KEY UPDATE ${cols.map((c) => `${c} = VALUES(${c})`).join(', ')}`,
      [userId, ...values],
    );
  }
  return readReminderSettings(pool, userId);
}

module.exports = { readReminderSettings, updateReminderSettings, DEFAULTS, COLUMNS };
