'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const { signToken } = require('../lib/tokens');
const { hashPassword, verifyPassword, DUMMY_HASH } = require('../lib/passwords');
const {
  findUserByEmail, findUserById, createUserWithPassword, findOrCreateGoogleUser,
  markEmailVerified, updatePasswordHash,
} = require('../db/users');
const { issueToken, consumeToken } = require('../lib/auth-tokens');
const { codeKey, normaliseCode, TTL_MINUTES } = require('../lib/auth-codes');
const { issueCode, checkCode } = require('../db/auth-codes');
const requireAuth = require('../middleware/require-auth');
const { renderPage, escapeHtml } = require('./auth-pages');

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

/// One answer for every failed code, whatever the reason -- unknown address,
/// wrong, expired, used up, already verified -- so the route cannot be used to
/// learn which accounts exist.
const codeInvalid = () => AppError.badRequest('CODE_INVALID', 'That code is wrong or has expired.');

/// The email as a code route receives it: trimmed and lowercased, or '' when
/// it is not a string. Deliberately not requireEmail, whose own 400 would
/// differ from CODE_INVALID and so reveal the difference it exists to hide.
const emailFrom = (value) => (typeof value === 'string' ? value.trim().toLowerCase() : '');

module.exports = function buildAuthRouter({
  pool, jwt, google, mail, publicBaseUrl = 'http://localhost:3000',
}) {
  const router = express.Router();

  // Derived on first use rather than here: some tests build the app without
  // a JWT config and never touch these routes.
  let key = null;
  const codesKey = () => {
    key = key || codeKey(jwt.secret);
    return key;
  };

  // Shared by /register and /verify-email/request. A failed send must never
  // fail the caller: the account exists and the code is already stored, so a
  // mail outage should leave the user able to ask for a new code, not unable
  // to have an account. A null code means the resend limit held it back.
  async function sendVerification(req, user) {
    const code = await issueCode(pool, {
      key: codesKey(), userId: user.user_id, purpose: 'verify_email',
    });
    if (code === null) return;
    try {
      await mail.send({
        to: user.email,
        subject: `Your FitSync code: ${code}`,
        text: `Enter this code in the FitSync app to verify your email: ${code}\n\n`
          + `It expires in ${TTL_MINUTES.verify_email} minutes. `
          + "If you didn't sign up for FitSync, you can ignore this email.",
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
      // proven by entering the emailed code.
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

  // The code typed into the app. Every failure is the same CODE_INVALID (see
  // codeInvalid). A malformed code or an unknown address never reaches
  // checkCode, so it spends nobody's attempts. Unknown addresses return a
  // little sooner than known ones; that is left alone, because /register
  // already answers EMAIL_TAKEN for a known address.
  router.post('/verify-email', async (req, res, next) => {
    try {
      const email = emailFrom(req.body.email);
      const code = normaliseCode(req.body.code);
      const user = email && code ? await findUserByEmail(pool, email) : null;
      const ok = Boolean(user && !user.email_verified && await checkCode(pool, {
        key: codesKey(), userId: user.user_id, purpose: 'verify_email', code,
      }));
      if (!ok) throw codeInvalid();
      await markEmailVerified(pool, user.user_id);
      res.json({ data: { verified: true } });
    } catch (err) { next(err); }
  });

  // Mirrors sendVerification above, with one deliberate difference: the mail
  // send itself is not awaited. See the comment on the send below.
  async function sendPasswordReset(req, user) {
    const token = await issueToken(pool, { userId: user.user_id, purpose: 'reset_password' });
    const link = `${publicBaseUrl}/api/v1/auth/password-reset?token=${token}`;
    // Not awaited, deliberately. Awaiting makes the verified branch
    // measurably slower than the unknown and unverified ones, which turns an
    // endpoint whose whole purpose is an indistinguishable 202 into a timing
    // oracle. The stub pushes to `sent` synchronously before it suspends, so
    // tests stay deterministic. (issueToken's DB insert above is still
    // awaited -- see the note on /password-reset/request for why that
    // residual timing difference is left alone rather than "fixed".)
    void mail.send({
      to: user.email,
      subject: 'Reset your FitSync password',
      text: `Use this link to reset your FitSync password:\n\n${link}\n\n`
        + 'This link works once and expires in 1 hour.',
    }).catch((err) => {
      req.log?.error({ err }, 'password reset email failed to send');
    });
  }

  // Always 202 with the same body, whether the address is unknown, known but
  // unverified, or known and verified. See the identical reasoning on
  // /verify-email/request and on login's INVALID_CREDENTIALS: anything that
  // differs by case here becomes an account-existence oracle.
  //
  // An unverified account is refused too, but silently, inside that same
  // 202 -- mailing a reset link to an address nobody has proven they own
  // would be a takeover path, not a recovery path.
  //
  // Known residual: the verified branch still awaits issueToken's INSERT
  // before responding, so it is marginally slower than the unknown/unverified
  // branches, which return after a single SELECT. Not closed here -- closing
  // it would mean a dummy INSERT (or similar) on every miss, which buys
  // nothing while POST /register already answers EMAIL_TAKEN for a known
  // address in one request. Recorded as a known limitation, not fixed.
  router.post('/password-reset/request', async (req, res, next) => {
    try {
      const email = requireString('email', req.body.email).toLowerCase();
      const user = await findUserByEmail(pool, email);
      if (user && user.email_verified) {
        await sendPasswordReset(req, user);
      }
      res.status(202).json({
        data: { message: 'If that account can receive a reset link, it is on its way.' },
      });
    } catch (err) { next(err); }
  });

  // Shared by the GET form below and the POST handler's own validation-
  // failure re-render, so a rejected password does not throw the user out of
  // the form -- they retry with the same token, still on the page, without
  // reopening the email.
  function renderResetForm({ token, message = null }) {
    return renderPage({
      title: 'Reset your password',
      body: `
${message ? `<p>${escapeHtml(message)}</p>` : ''}
<p>Choose a new password for your FitSync account.</p>
<form method="POST" action="/api/v1/auth/password-reset">
  <input type="hidden" name="token" value="${escapeHtml(token)}">
  <label for="password">New password</label>
  <input type="password" id="password" name="password" required
         minlength="${MIN_PASSWORD_LENGTH}" maxlength="${MAX_PASSWORD_LENGTH}">
  <button type="submit">Reset password</button>
</form>`,
    });
  }

  // Renders the form only -- does NOT consume the token. Only the POST below
  // does. If the GET consumed it, merely opening the link (or a mail client
  // prefetching it) would burn the reset before the user typed anything.
  router.get('/password-reset', (req, res) => {
    const token = typeof req.query.token === 'string' ? req.query.token : '';
    // Carries a live, single-use token in a hidden field -- must never be
    // cached (by a shared proxy, a browser's back/forward cache, ...) where
    // a later visitor to the same URL could read it out of the page.
    res.status(200).set('Cache-Control', 'no-store').send(renderResetForm({ token }));
  });

  // The only route that spends a reset token. Deliberately server-rendered,
  // not JSON: the spec chose this over a deep link into the Flutter client,
  // so there is no JSON twin of this route -- that would be a second, unused
  // way to spend a high-value credential.
  router.post('/password-reset', express.urlencoded({ extended: false }), async (req, res, next) => {
    try {
      const token = typeof req.body.token === 'string' ? req.body.token : '';
      // Validate BEFORE consuming. consumeToken marks the row spent
      // unconditionally, so if a too-short password were checked after, a
      // mistyped password would irreversibly burn the one-time link over a
      // mistake that has nothing to do with the token's validity. Validation
      // is pure and touches no state, so it is safe to run first.
      //
      // Opened straight out of a mail client: on failure, re-render the same
      // form with the token intact and a message, rather than throwing --
      // otherwise the user loses both the form and what they typed, over a
      // mistake that has nothing to do with the link itself.
      let password;
      try {
        password = requireString('password', req.body.password, {
          minLength: MIN_PASSWORD_LENGTH, maxLength: MAX_PASSWORD_LENGTH,
        });
      } catch (validationErr) {
        if (!(validationErr instanceof AppError)) throw validationErr;
        res.status(400).set('Cache-Control', 'no-store')
          .send(renderResetForm({ token, message: validationErr.message }));
        return;
      }
      const result = await consumeToken(pool, { token: req.body.token, purpose: 'reset_password' });
      if (!result) {
        res.status(400).send(renderPage({
          title: 'Reset link invalid',
          body: '<p>This password reset link is invalid or has expired. '
            + 'Request a new one and try again.</p>',
        }));
        return;
      }
      await updatePasswordHash(pool, result.userId, await hashPassword(password));
      res.status(200).send(renderPage({
        title: 'Password reset',
        body: '<p>Your password has been reset. You can sign in to FitSync now.</p>',
      }));
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
