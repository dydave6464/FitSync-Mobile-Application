'use strict';
const express = require('express');
const helmet = require('helmet');
const AppError = require('../lib/app-error');
const requireAuth = require('../middleware/require-auth');
const { confirmPassword } = require('../lib/passwords');
const { findLiveToken, TTL_SECONDS } = require('../lib/auth-tokens');
const { findUserById, findUserByEmail } = require('../db/users');
const {
  deleteUser, deleteUserByToken, isGoogleIdentityOf, issueDeleteLink,
} = require('../db/account');
const { renderPage, escapeHtml } = require('./auth-pages');

const LINK_MINUTES = TTL_SECONDS.delete_account / 60;
const MAX_EMAIL_LENGTH = 255;

const reauthRequired = () => AppError.badRequest(
  'REAUTH_REQUIRED', "Confirm it's you to delete your account.",
);

/// A Google sign-in that does not verify has not confirmed anything, so it
/// is REAUTH_REQUIRED: the contract's errors here are 400s, and a 401 would
/// read to the app as its own session ending. Only a bad token is mapped; a
/// verifier that cannot reach Google still fails as a server error.
async function verifyGoogleReauth(google, idToken) {
  try {
    return await google.verifyIdToken(idToken);
  } catch (err) {
    if (err instanceof AppError && err.code === 'INVALID_GOOGLE_TOKEN') throw reauthRequired();
    throw err;
  }
}

const p = (text) => `<p>${escapeHtml(text)}</p>`;

// What deletion removes, said once for the request page and the confirm page.
const WHAT_GOES = `${p('Deleting your FitSync account removes everything it holds:')}
<ul>
<li>your profile and health answers</li>
<li>your workout plans, sessions and progress</li>
<li>your meals, weigh-ins, goals, routines and reminders</li>
<li>your Pro payment history</li>
</ul>
${p("It can't be undone.")}`;

const SENT_PAGE = (base) => renderPage({
  title: 'Check your email',
  body: `${p("If an account uses this email, we've sent a link to delete it.")}
${p(`The link works once and expires in ${LINK_MINUTES} minutes.`)}
<p><a href="${escapeHtml(base)}/delete-request">Back</a></p>`,
});

const EXPIRED_PAGE = (base) => renderPage({
  title: 'Link expired',
  body: `${p('This link has expired. Ask for a new one.')}
<p><a href="${escapeHtml(base)}/delete-request">Ask for a new link</a></p>`,
});

/// Deleting the account (spec 2026-11-06-account-deletion): from the app
/// once the user re-confirms, and from a web page Google Play links to, by
/// an emailed single-use link. Both delete through db/account.js's
/// deleteUser. Logs carry user ids only, never an email or a token.
module.exports = function buildAccountRouter(deps) {
  const router = express.Router();
  const { pool, jwt, google, mail } = deps;
  // The email link's origin comes from config alone, never from the request:
  // a Host header is the caller's to choose, and a forged one would mail the
  // account's owner a working delete link that points at someone else's site.
  const publicBaseUrl = (deps.publicBaseUrl || 'http://localhost:3000').replace(/\/+$/, '');

  // POST, not DELETE: the app's client sends no body with DELETE. A password
  // account confirms with its password, an account with a Google identity
  // with a fresh Google sign-in; anything else is REAUTH_REQUIRED.
  router.post('/delete', requireAuth({ pool, jwt }), async (req, res, next) => {
    try {
      const user = await findUserById(pool, req.user.userId);
      if (!user) {
        throw AppError.unauthorized('UNAUTHENTICATED', 'Sign in again to continue.');
      }
      const { password, idToken } = req.body ?? {};
      if (typeof password === 'string' && user.password_hash !== null) {
        // The same check as POST /auth/password: 400 WRONG_PASSWORD.
        await confirmPassword(password, user.password_hash);
      } else if (typeof idToken === 'string' && Number(user.has_google) === 1) {
        const identity = await verifyGoogleReauth(google, idToken);
        if (!await isGoogleIdentityOf(pool, user.user_id, identity.subject)) {
          throw AppError.badRequest(
            'GOOGLE_ACCOUNT_MISMATCH', "That Google account isn't the one this account uses.",
          );
        }
      } else {
        throw reauthRequired();
      }
      await deleteUser(pool, user.user_id);
      req.log?.info({ userId: user.user_id }, 'account deleted');
      res.status(204).end();
    } catch (err) { next(err); }
  });

  // The web pages. Opened from a browser or a mail client with no app
  // sign-in. No page is cached or indexed: the confirm page carries a live
  // link in its form. The CSP is helmet's minus upgrade-insecure-requests,
  // which would turn the form's POST into https on a plain-http host (the
  // phone hotspot) -- as routes/pro.js does for its stub page. Over https it
  // changes nothing.
  router.use(
    '/delete-request',
    helmet.contentSecurityPolicy({ useDefaults: true, directives: { upgradeInsecureRequests: null } }),
    (_req, res, next) => {
      res.set('Cache-Control', 'no-store');
      res.set('X-Robots-Tag', 'noindex, nofollow');
      next();
    },
  );
  const formBody = express.urlencoded({ extended: false, limit: '8kb' });

  router.get('/delete-request', (req, res) => {
    const base = escapeHtml(req.baseUrl);
    res.type('html').send(renderPage({
      title: 'Delete your FitSync account',
      body: `${WHAT_GOES}
${p("In the app, go to Settings, then Delete account. Or enter your account's email and we'll send you a link to confirm.")}
<form method="post" action="${base}/delete-request">
<label for="email">Email</label>
<input id="email" name="email" type="email" autocomplete="email" required maxlength="${MAX_EMAIL_LENGTH}">
<button type="submit">Email me the link</button>
</form>`,
    }));
  });

  // Always the same page, whether or not an account uses the email: the page
  // must never say which addresses have accounts. The mail send is not
  // awaited, so it adds no time to the known branch. Known residual, as on
  // POST /auth/password-reset/request: the known branch still awaits
  // issueDeleteLink's queries, so it is marginally slower -- low value next to
  // /auth/register, which answers EMAIL_TAKEN in one request.
  router.post('/delete-request', formBody, async (req, res, next) => {
    try {
      const raw = req.body?.email;
      const email = typeof raw === 'string' ? raw.trim().toLowerCase() : '';
      const user = email && email.length <= MAX_EMAIL_LENGTH
        ? await findUserByEmail(pool, email) : null;
      const token = user ? await issueDeleteLink(pool, user.user_id) : null;
      if (token) {
        const link = `${publicBaseUrl}${req.baseUrl}/delete-request/confirm?token=${token}`;
        void mail.send({
          to: user.email,
          subject: 'Delete your FitSync account',
          text: `Open this link to delete your FitSync account and all its data:\n${link}\n\n`
            + `It works once and expires in ${LINK_MINUTES} minutes. `
            + "If you didn't ask to delete your account, you can ignore this email "
            + "— your account hasn't changed.",
        }).catch((err) => {
          req.log?.error({ err }, 'account deletion email failed to send');
        });
      }
      res.type('html').send(SENT_PAGE(req.baseUrl));
    } catch (err) { next(err); }
  });

  // Opening the link shows what goes and a button; only the POST spends it,
  // so a mail scanner that follows links cannot delete anyone.
  router.get('/delete-request/confirm', async (req, res, next) => {
    try {
      const { token } = req.query;
      if (!await findLiveToken(pool, { token, purpose: 'delete_account' })) {
        res.status(404).type('html').send(EXPIRED_PAGE(req.baseUrl));
        return;
      }
      res.type('html').send(renderPage({
        title: 'Delete your account?',
        body: `${WHAT_GOES}
<form method="post" action="${escapeHtml(req.baseUrl)}/delete-request/confirm">
<input type="hidden" name="token" value="${escapeHtml(token)}">
<button type="submit" class="danger">Delete my account</button>
</form>
${p('To keep your account, close this page.')}`,
      }));
    } catch (err) { next(err); }
  });

  router.post('/delete-request/confirm', formBody, async (req, res, next) => {
    try {
      const userId = await deleteUserByToken(pool, req.body?.token);
      if (userId === null) {
        res.status(404).type('html').send(EXPIRED_PAGE(req.baseUrl));
        return;
      }
      req.log?.info({ userId }, 'account deleted from the web page');
      res.type('html').send(renderPage({
        title: 'Account deleted',
        body: p('Your account and its data were deleted.'),
      }));
    } catch (err) { next(err); }
  });

  return router;
};
