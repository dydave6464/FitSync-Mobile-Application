'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const { signToken } = require('../lib/tokens');
const { hashPassword, verifyPassword, DUMMY_HASH } = require('../lib/passwords');
const {
  findUserByEmail, findUserById, createUserWithPassword, findOrCreateGoogleUser, markEmailVerified,
} = require('../db/users');
const { issueToken, consumeToken } = require('../lib/auth-tokens');
const requireAuth = require('../middleware/require-auth');

const MIN_PASSWORD_LENGTH = 8;
// bcrypt (via bcryptjs) only reads the first 72 bytes of its input — anything
// beyond that contributes nothing to the hash. Without a cap, an anonymous
// caller can send an arbitrarily large password and force the server to spend
// real CPU running it through a deliberately slow hash function: a cheap
// denial-of-service against the one route that has no auth to gate it.
const MAX_PASSWORD_LENGTH = 72;
// users.email and users.full_name are both VARCHAR(255). Anything longer must
// be rejected here as a 400, not discovered as ER_DATA_TOO_LONG from MySQL —
// see the identical MAX_LENGTH map in src/routes/profile.js.
const MAX_STRING_LENGTH = 255;

// The row carries password_hash. Nothing outside this module may see it.
function toPublicUser(row) {
  return {
    userId: row.user_id,
    email: row.email,
    fullName: row.full_name,
    onboardingCompleted: row.onboarding_completed_at !== null,
    isPremium: Boolean(row.is_premium),
    emailVerified: Boolean(row.email_verified),
  };
}

function requireString(field, value, { minLength = 1, maxLength = null } = {}) {
  if (typeof value !== 'string' || value.trim().length < minLength) {
    throw AppError.badRequest(
      'INVALID_PROFILE_FIELD',
      `${field} must be a string of at least ${minLength} characters.`,
      [{ field }],
    );
  }
  const trimmed = value.trim();
  if (maxLength !== null && trimmed.length > maxLength) {
    throw AppError.badRequest(
      'INVALID_PROFILE_FIELD',
      `${field} must be at most ${maxLength} characters.`,
      [{ field }],
    );
  }
  return trimmed;
}

// Deliberately loose. This rejects values that cannot be an address at all --
// no @, no dot in the domain, whitespace -- and nothing more. It is a
// data-quality control, NOT a security one: test@gmail.com is perfectly valid
// and belongs to someone else. Only verification addresses that. A stricter
// pattern would reject real addresses, which is a worse failure.
const EMAIL_SHAPE = /^[^\s@]+@[^\s@.]+\.[^\s@]+$/;

function requireEmail(value) {
  const email = requireString('email', value, { maxLength: MAX_STRING_LENGTH }).toLowerCase();
  if (!EMAIL_SHAPE.test(email)) {
    throw AppError.badRequest(
      'INVALID_PROFILE_FIELD', 'email must be a valid email address.', [{ field: 'email' }],
    );
  }
  return email;
}

// Minimal, self-contained response for the verify-email link -- Task 5 will
// factor this out into a shared page helper (server/src/routes/auth-pages.js)
// used by the password-reset pages too. Kept deliberately plain: this is
// clicked from a mail client, not part of the app's own UI.
function renderMinimalPage(title, message) {
  return `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>${title}</title></head>
<body>
<h1>${title}</h1>
<p>${message}</p>
</body>
</html>`;
}

module.exports = function buildAuthRouter({
  pool, jwt, google, mail, publicBaseUrl = 'http://localhost:3000',
}) {
  const router = express.Router();

  // Shared by /register and /verify-email/request. A failed send must never
  // fail the caller: the account exists and the token is already stored, so
  // a mail outage should leave the user able to ask for a resend, not unable
  // to have an account.
  async function sendVerification(req, user) {
    const token = await issueToken(pool, {
      userId: user.user_id, purpose: 'verify_email',
    });
    const link = `${publicBaseUrl}/api/v1/auth/verify-email?token=${token}`;
    try {
      await mail.send({
        to: user.email,
        subject: 'Verify your FitSync email',
        text: `Confirm your address to finish setting up FitSync:\n\n${link}\n\n`
          + 'This link works once and expires in 24 hours.',
      });
    } catch (err) {
      req.log?.error({ err }, 'verification email failed to send');
    }
  }

  router.post('/register', async (req, res, next) => {
    try {
      const email = requireEmail(req.body.email);
      const password = requireString('password', req.body.password, {
        minLength: MIN_PASSWORD_LENGTH,
        maxLength: MAX_PASSWORD_LENGTH,
      });
      const fullName = requireString('fullName', req.body.fullName, { maxLength: MAX_STRING_LENGTH });

      if (await findUserByEmail(pool, email)) {
        throw AppError.conflict('EMAIL_TAKEN', 'That email is already registered.');
      }

      const user = await createUserWithPassword(pool, {
        email, passwordHash: await hashPassword(password), fullName,
      });
      await sendVerification(req, user);
      // Hard gate: no token here. Nothing is signed in until the address is
      // proven by following the verification link.
      res.status(201).json({ data: { user: toPublicUser(user) } });
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
      // AFTER the compare, never before. Before it, anyone could learn whether
      // an address is registered without knowing its password -- exactly what
      // the DUMMY_HASH dance above exists to prevent. Reaching this line
      // already required the correct password, so disclosing the account's
      // state costs nothing further.
      if (!user.email_verified) {
        throw AppError.forbidden(
          'EMAIL_NOT_VERIFIED', 'Check your email to finish setting up your account.',
        );
      }

      res.json({ data: { user: toPublicUser(user), token: signToken(user.user_id, jwt) } });
    } catch (err) { next(err); }
  });

  // Re-authenticates by email + password, because under a hard gate the
  // caller has no JWT yet -- registration issued none. Responds 202 with an
  // identical body whether the credentials were right, wrong, or the account
  // was already verified. Anything that differs by case here becomes exactly
  // the account-existence oracle login's DUMMY_HASH dance exists to prevent,
  // so this route runs the same always-compare dance for the same reason.
  router.post('/verify-email/request', async (req, res, next) => {
    try {
      const email = requireString('email', req.body.email).toLowerCase();
      const password = requireString('password', req.body.password);

      const user = await findUserByEmail(pool, email);
      const hash = (user && user.password_hash) || DUMMY_HASH;
      const matches = await verifyPassword(password, hash);
      const ok = Boolean(user && user.password_hash && matches);

      if (ok && !user.email_verified) {
        await sendVerification(req, user);
      }

      res.status(202).json({
        data: { message: 'If that account needs verifying, an email is on its way.' },
      });
    } catch (err) { next(err); }
  });

  router.get('/verify-email', async (req, res, next) => {
    try {
      const result = await consumeToken(pool, { token: req.query.token, purpose: 'verify_email' });
      if (!result) {
        throw AppError.badRequest(
          'INVALID_VERIFICATION_TOKEN', 'This verification link is invalid or has expired.',
        );
      }
      await markEmailVerified(pool, result.userId);
      res.status(200).send(renderMinimalPage(
        'Email verified', 'Your address is verified. You can sign in to FitSync now.',
      ));
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
