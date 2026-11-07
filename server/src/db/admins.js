'use strict';
const { hashPassword, MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH } = require('../lib/passwords');
const { findUserByEmail } = require('./users');

// The row carries password_hash: routes hand out toPublicAdmin (routes/admin.js).
const ADMIN_COLUMNS = 'admin_id, email, password_hash, full_name, created_at';

// admins.email and admins.full_name are VARCHAR(255) (001).
const MAX_STRING_LENGTH = 255;

// The same deliberately loose shape as EMAIL_SHAPE in routes/auth.js: it
// rejects what cannot be an address at all, nothing more.
const EMAIL_SHAPE = /^[^\s@]+@[^\s@.]+\.[^\s@]+$/;

async function findAdminByEmail(pool, email) {
  // As findUserByEmail: the collation is already case-insensitive, LOWER()
  // states the intent and survives a collation change.
  const [rows] = await pool.query(
    `SELECT ${ADMIN_COLUMNS} FROM admins WHERE LOWER(email) = LOWER(?)`, [email],
  );
  return rows[0] || null;
}

async function findAdminById(pool, adminId) {
  const [rows] = await pool.query(
    `SELECT ${ADMIN_COLUMNS} FROM admins WHERE admin_id = ?`, [adminId],
  );
  return rows[0] || null;
}

function refusal(code, message) {
  const err = new Error(message);
  err.code = code;
  return err;
}

/// `npm run admin:create`'s work. The rules a trainee's registration applies
/// (email shape, password length, trimmed as login trims) plus one more: an
/// email is either an admin's or a trainee's, never both, because sign-in
/// looks the address up in admins first. Throws an Error whose .code is
/// INVALID_EMAIL, INVALID_NAME, PASSWORD_TOO_SHORT, PASSWORD_TOO_LONG or
/// EMAIL_IN_USE; nothing is written then.
async function createAdminAccount(pool, { email, fullName, password }) {
  const address = typeof email === 'string' ? email.trim().toLowerCase() : '';
  if (address.length > MAX_STRING_LENGTH || !EMAIL_SHAPE.test(address)) {
    throw refusal('INVALID_EMAIL', "That isn't a valid email address.");
  }
  const name = typeof fullName === 'string' ? fullName.trim() : '';
  if (name.length === 0 || name.length > MAX_STRING_LENGTH) {
    throw refusal('INVALID_NAME', `The name must be 1 to ${MAX_STRING_LENGTH} characters.`);
  }
  // Login trims the password it is given (routes/auth.js requireString), so
  // the hash must be of the trimmed one, as registration's is.
  const plain = typeof password === 'string' ? password.trim() : '';
  if (plain.length < MIN_PASSWORD_LENGTH) {
    throw refusal('PASSWORD_TOO_SHORT', `The password must be at least ${MIN_PASSWORD_LENGTH} characters.`);
  }
  if (plain.length > MAX_PASSWORD_LENGTH) {
    throw refusal('PASSWORD_TOO_LONG', `The password must be at most ${MAX_PASSWORD_LENGTH} characters.`);
  }
  const inUse = () => refusal('EMAIL_IN_USE', 'That email is already used by an admin or a trainee.');
  if (await findUserByEmail(pool, address) || await findAdminByEmail(pool, address)) throw inUse();

  try {
    const [result] = await pool.query(
      'INSERT INTO admins (email, password_hash, full_name) VALUES (?, ?, ?)',
      [address, await hashPassword(plain), name],
    );
    return { adminId: result.insertId };
  } catch (err) {
    // Another admin:create for the same address landed between the check and here.
    if (err.code === 'ER_DUP_ENTRY') throw inUse();
    throw err;
  }
}

module.exports = { findAdminByEmail, findAdminById, createAdminAccount };
