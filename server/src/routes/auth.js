'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const { signToken } = require('../lib/tokens');
const { hashPassword, verifyPassword, DUMMY_HASH } = require('../lib/passwords');
const {
  findUserByEmail, findUserById, createUserWithPassword, findOrCreateGoogleUser,
} = require('../db/users');
const requireAuth = require('../middleware/require-auth');

const MIN_PASSWORD_LENGTH = 8;

// The row carries password_hash. Nothing outside this module may see it.
function toPublicUser(row) {
  return {
    userId: row.user_id,
    email: row.email,
    fullName: row.full_name,
    onboardingCompleted: row.onboarding_completed_at !== null,
    isPremium: Boolean(row.is_premium),
  };
}

function requireString(field, value, { minLength = 1 } = {}) {
  if (typeof value !== 'string' || value.trim().length < minLength) {
    throw AppError.badRequest(
      'INVALID_PROFILE_FIELD',
      `${field} must be a string of at least ${minLength} characters.`,
      [{ field }],
    );
  }
  return value.trim();
}

module.exports = function buildAuthRouter({ pool, jwt, google }) {
  const router = express.Router();

  router.post('/register', async (req, res, next) => {
    try {
      const email = requireString('email', req.body.email).toLowerCase();
      const password = requireString('password', req.body.password, { minLength: MIN_PASSWORD_LENGTH });
      const fullName = requireString('fullName', req.body.fullName);

      if (await findUserByEmail(pool, email)) {
        throw AppError.conflict('EMAIL_TAKEN', 'That email is already registered.');
      }

      const user = await createUserWithPassword(pool, {
        email, passwordHash: await hashPassword(password), fullName,
      });
      res.status(201).json({
        data: { user: toPublicUser(user), token: signToken(user.user_id, jwt) },
      });
    } catch (err) { next(err); }
  });

  router.post('/login', async (req, res, next) => {
    try {
      const email = requireString('email', req.body.email).toLowerCase();
      const password = requireString('password', req.body.password);

      const user = await findUserByEmail(pool, email);
      // One error, one message, whether the email is unknown or the password is
      // wrong. Anything else turns this route into an account-existence oracle.
      //
      // That includes timing: always compare against SOME bcrypt hash, even
      // when there is no user or no real password_hash (a Google-only
      // account), so an unknown email and a known email both pay the same
      // bcrypt cost. Short-circuiting the compare for either case would let
      // response latency leak exactly what the identical error is supposed
      // to hide.
      const hash = (user && user.password_hash) || DUMMY_HASH;
      const matches = await verifyPassword(password, hash);
      const ok = Boolean(user && user.password_hash && matches);
      if (!ok) {
        throw AppError.unauthorized('INVALID_CREDENTIALS', 'Email or password is incorrect.');
      }

      res.json({ data: { user: toPublicUser(user), token: signToken(user.user_id, jwt) } });
    } catch (err) { next(err); }
  });

  router.post('/google', async (req, res, next) => {
    try {
      const idToken = requireString('idToken', req.body.idToken);
      const identity = await google.verifyIdToken(idToken);
      const { user, isNew } = await findOrCreateGoogleUser(pool, identity);
      res.json({
        data: {
          user: toPublicUser(user),
          token: signToken(user.user_id, jwt),
          isNewUser: isNew,
        },
      });
    } catch (err) { next(err); }
  });

  router.get('/me', requireAuth({ pool, jwt }), async (req, res, next) => {
    try {
      const user = await findUserById(pool, req.user.userId);
      // requireAuth already confirmed this user existed a moment ago, but the
      // account can be deleted in the window between that check and this
      // lookup. Without this guard toPublicUser(null) throws a TypeError and
      // the client gets a 500 for what is really the same "sign in again"
      // case requireAuth already handles.
      if (!user) {
        throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
      }
      res.json({ data: { user: toPublicUser(user) } });
    } catch (err) { next(err); }
  });

  return router;
};

module.exports.toPublicUser = toPublicUser;
module.exports.requireString = requireString;
