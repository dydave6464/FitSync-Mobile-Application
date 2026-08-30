'use strict';

// API name -> column. Anything not in this map cannot be written, which is what
// keeps PATCH from becoming a way to set is_premium or onboarding_completed_at.
const WRITABLE = {
  fullName: 'full_name',
  sex: 'sex',
  dateOfBirth: 'date_of_birth',
  heightCm: 'height_cm',
  weightKg: 'weight_kg',
  goalWeightKg: 'goal_weight_kg',
  mainGoal: 'main_goal',
  fitnessLevel: 'fitness_level',
  activityLevel: 'activity_level',
  trainingLocation: 'training_location',
  city: 'city',
  notificationsEnabled: 'notifications_enabled',
};

async function getProfile(pool, userId) {
  const [rows] = await pool.query(
    `SELECT user_id, email, full_name, sex, date_of_birth, height_cm, weight_kg,
            goal_weight_kg, main_goal, fitness_level, activity_level,
            training_location, city, is_premium, notifications_enabled,
            onboarding_completed_at
       FROM users WHERE user_id = ?`, [userId],
  );
  if (rows.length === 0) return null;
  const u = rows[0];

  const [equipment] = await pool.query(
    // COALESCE so a selection that predates curation still renders rather than
    // coming back as a null name.
    `SELECT e.equipment_id, COALESCE(e.display_name, e.name) AS name
       FROM user_equipment ue
       JOIN equipment e ON e.equipment_id = ue.equipment_id
      WHERE ue.user_id = ? ORDER BY e.display_order, e.name`, [userId],
  );
  const [injuries] = await pool.query(
    `SELECT i.injury_id, i.name, i.is_lateral, i.region_group, ui.side
       FROM user_injuries ui
       JOIN injuries i ON i.injury_id = ui.injury_id
      WHERE ui.user_id = ? ORDER BY i.name`, [userId],
  );

  return {
    userId: u.user_id,
    email: u.email,
    fullName: u.full_name,
    sex: u.sex,
    dateOfBirth: u.date_of_birth,
    heightCm: u.height_cm,
    weightKg: u.weight_kg,
    goalWeightKg: u.goal_weight_kg,
    mainGoal: u.main_goal,
    fitnessLevel: u.fitness_level,
    activityLevel: u.activity_level,
    trainingLocation: u.training_location,
    city: u.city,
    isPremium: Boolean(u.is_premium),
    notificationsEnabled: Boolean(u.notifications_enabled),
    onboardingCompleted: u.onboarding_completed_at !== null,
    equipment: equipment.map((e) => ({ equipmentId: e.equipment_id, name: e.name })),
    injuries: injuries.map((i) => ({
      injuryId: i.injury_id,
      name: i.name,
      isLateral: Boolean(i.is_lateral),
      regionGroup: i.region_group,
      side: i.side,
    })),
  };
}

async function updateProfile(pool, userId, fields) {
  const sets = [];
  const params = [];
  for (const [key, column] of Object.entries(WRITABLE)) {
    if (Object.prototype.hasOwnProperty.call(fields, key)) {
      sets.push(`${column} = ?`);
      params.push(fields[key]);
    }
  }
  // A step where the user changed nothing still submits. That is not an error.
  if (sets.length === 0) return;
  params.push(userId);
  await pool.query(`UPDATE users SET ${sets.join(', ')} WHERE user_id = ?`, params);
}

async function setEquipment(pool, userId, equipmentIds) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query('DELETE FROM user_equipment WHERE user_id = ?', [userId]);
    for (const id of equipmentIds) {
      await conn.query(
        'INSERT INTO user_equipment (user_id, equipment_id) VALUES (?, ?)', [userId, id],
      );
    }
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

async function setInjuries(pool, userId, entries) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query('DELETE FROM user_injuries WHERE user_id = ?', [userId]);
    for (const { injuryId, side } of entries) {
      await conn.query(
        'INSERT INTO user_injuries (user_id, injury_id, side) VALUES (?, ?, ?)',
        [userId, injuryId, side || null],
      );
    }
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

async function listEquipment(pool) {
  // Only the curated chips. Raw catalogue tags stay out of onboarding; see
  // seed-equipment.js for what promotes a row into this list.
  const [rows] = await pool.query(
    `SELECT equipment_id, display_name FROM equipment
      WHERE is_user_selectable = 1
      ORDER BY display_order`,
  );
  return rows.map((r) => ({ equipmentId: r.equipment_id, name: r.display_name }));
}

async function listInjuries(pool) {
  const [rows] = await pool.query(
    'SELECT injury_id, name, is_lateral, region_group FROM injuries ORDER BY region_group, name',
  );
  return rows.map((r) => ({
    injuryId: r.injury_id,
    name: r.name,
    isLateral: Boolean(r.is_lateral),
    regionGroup: r.region_group,
  }));
}

async function markOnboardingComplete(pool, userId) {
  await pool.query(
    'UPDATE users SET onboarding_completed_at = CURRENT_TIMESTAMP WHERE user_id = ?', [userId],
  );
}

module.exports = {
  getProfile, updateProfile, setEquipment, setInjuries,
  listEquipment, listInjuries, markOnboardingComplete, WRITABLE,
};
