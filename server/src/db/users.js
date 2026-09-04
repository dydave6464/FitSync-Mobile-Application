'use strict';
const AppError = require('../lib/app-error');

const USER_COLUMNS = `
  user_id, email, password_hash, full_name, sex, date_of_birth,
  height_cm, weight_kg, goal_weight_kg, main_goal, fitness_level,
  activity_level, training_location, city, is_premium,
  notifications_enabled, onboarding_completed_at, email_verified, created_at
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

// The one place email_verified flips from 0 to 1. Used both by the
// verify-email route (a token proved the address) and by
// findOrCreateGoogleUser (Google already vouched for it).
async function markEmailVerified(pool, userId) {
  await pool.query('UPDATE users SET email_verified = 1 WHERE user_id = ?', [userId]);
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
    // Google re-vouches for the address on every sign-in, not only the first.
    // If the account was ever created or later changed to be unverified
    // through some other path, a fresh Google sign-in is itself proof.
    await markEmailVerified(pool, existing[0].user_id);
    return { user: await findUserById(pool, existing[0].user_id), isNew: false };
  }

  // From here on, every branch either links to an account found by email or
  // creates a new one carrying that email, so an unverified email can no
  // longer be trusted — and it must be checked here, before branch 2, not
  // inside it. Gating only inside branch 2 leaves branch 3 open to a
  // two-call pre-hijack: an attacker signs in first with an unverified token
  // for the victim's address (branch 3 would create the account
  // unconditionally), then the real victim signs in later with a genuinely
  // verified token; branch 2's own gate checks only *that* call's
  // verification and happily links the victim's real identity into the
  // account the attacker already controls. Do not move this check back
  // inside branch 2.
  if (!email || !emailVerified) {
    throw AppError.unauthorized(
      'INVALID_GOOGLE_TOKEN',
      'Google sign-in could not be verified.',
    );
  }

  // 2. An account already exists on this email. Linking is right — one person,
  //    one account — now that Google has vouched for the address above.
  const byEmail = await findUserByEmail(pool, email);
  if (byEmail) {
    await pool.query(
      'INSERT INTO user_identities (user_id, provider, provider_subject) VALUES (?, ?, ?)',
      [byEmail.user_id, 'google', subject],
    );
    // This account may have been created by password registration and never
    // verified. Google has now proven the same address, so the account is as
    // verified as a brand-new Google signup would be.
    await markEmailVerified(pool, byEmail.user_id);
    return { user: await findUserById(pool, byEmail.user_id), isNew: false };
  }

  // 3. Brand new person. password_hash stays NULL — there is no password.
  // Google already vouched for the address (checked above), so the account
  // is created verified — no separate email loop for a Google signup.
  const [result] = await pool.query(
    'INSERT INTO users (email, password_hash, full_name, email_verified) VALUES (?, NULL, ?, 1)',
    [email, fullName || 'FitSync user'],
  );
  await pool.query(
    'INSERT INTO user_identities (user_id, provider, provider_subject) VALUES (?, ?, ?)',
    [result.insertId, 'google', subject],
  );
  return { user: await findUserById(pool, result.insertId), isNew: true };
}

module.exports = {
  findUserByEmail, findUserById, createUserWithPassword, findOrCreateGoogleUser, markEmailVerified,
};
