'use strict';
const AppError = require('../lib/app-error');

const USER_COLUMNS = `
  user_id, email, password_hash, full_name, sex, date_of_birth,
  height_cm, weight_kg, goal_weight_kg, main_goal, fitness_level,
  activity_level, training_location, city, is_premium,
  notifications_enabled, onboarding_completed_at, created_at
`;

async function findUserByEmail(pool, email) {
  // utf8mb4_unicode_ci is already case-insensitive, but LOWER() makes the
  // intent explicit and survives a collation change.
  const [rows] = await pool.query(
    `SELECT ${USER_COLUMNS} FROM users WHERE LOWER(email) = LOWER(?)`, [email],
  );
  return rows[0] || null;
}

async function findUserById(pool, userId) {
  const [rows] = await pool.query(
    `SELECT ${USER_COLUMNS} FROM users WHERE user_id = ?`, [userId],
  );
  return rows[0] || null;
}

async function createUserWithPassword(pool, { email, passwordHash, fullName }) {
  const [result] = await pool.query(
    'INSERT INTO users (email, password_hash, full_name) VALUES (?, ?, ?)',
    [email, passwordHash, fullName],
  );
  return findUserById(pool, result.insertId);
}

async function findOrCreateGoogleUser(pool, identity) {
  const { subject, email, emailVerified, fullName } = identity;

  // 1. Known identity: sub is stable across email changes, so match on it first.
  const [existing] = await pool.query(
    `SELECT u.user_id FROM user_identities i
       JOIN users u ON u.user_id = i.user_id
      WHERE i.provider = 'google' AND i.provider_subject = ?`,
    [subject],
  );
  if (existing.length > 0) {
    return { user: await findUserById(pool, existing[0].user_id), isNew: false };
  }

  // 2. An account already exists on this email. Linking is right — one person,
  //    one account — but only on Google's word that they own the address.
  const byEmail = email ? await findUserByEmail(pool, email) : null;
  if (byEmail) {
    if (!emailVerified) {
      throw AppError.unauthorized(
        'INVALID_GOOGLE_TOKEN',
        'Google sign-in could not be verified.',
      );
    }
    await pool.query(
      'INSERT INTO user_identities (user_id, provider, provider_subject) VALUES (?, ?, ?)',
      [byEmail.user_id, 'google', subject],
    );
    return { user: await findUserById(pool, byEmail.user_id), isNew: false };
  }

  // 3. Brand new person. password_hash stays NULL — there is no password.
  const [result] = await pool.query(
    'INSERT INTO users (email, password_hash, full_name) VALUES (?, NULL, ?)',
    [email, fullName || 'FitSync user'],
  );
  await pool.query(
    'INSERT INTO user_identities (user_id, provider, provider_subject) VALUES (?, ?, ?)',
    [result.insertId, 'google', subject],
  );
  return { user: await findUserById(pool, result.insertId), isNew: true };
}

module.exports = {
  findUserByEmail, findUserById, createUserWithPassword, findOrCreateGoogleUser,
};
