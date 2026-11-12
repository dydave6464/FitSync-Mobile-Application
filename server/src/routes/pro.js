'use strict';
const express = require('express');
const helmet = require('helmet');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { PLANS, PLAN_TERMS } = require('../lib/pro-plans');
const {
  proStatus, createPayment, setCheckoutSession, findPayment, recentPendingPayments, completePayment,
} = require('../db/pro');
const { renderPage, escapeHtml } = require('./auth-pages');

// The same test config/index.js applies to PUBLIC_BASE_URL in production.
const LOCALHOST = /^https?:\/\/(localhost|127(?:\.\d{1,3}){3})(?::\d+)?(?:\/|$)/i;
const OPEN_FAILED = "Couldn't open the payment page. Try again.";
const CHECK_FAILED = "Couldn't check your payment. Your money is safe — try again.";
const unavailable = (status, message) => new AppError(status, 'PAYMENTS_UNAVAILABLE', message);
const PRICES = { monthly: PLANS.monthly.pricePhp, annual: PLANS.annual.pricePhp };

/// Buying Pro (spec 2026-10-26-pro-payments-design). The server creates
/// PayMongo's checkout for its own price and confirms a payment by asking
/// PayMongo -- never by trusting the app -- so no webhook and no public
/// address are needed. A status read also finishes the caller's recent
/// attempts that were paid while the app wasn't watching. Logs carry ids and
/// statuses only.
module.exports = function buildProRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);
  const { pool, payments, publicBaseUrl } = deps;
  const checkBudgetMs = deps.proStatusCheckMs ?? 3000;
  const log = (req) => req.log ?? deps.logger;
  // prices stays for apps already installed. plans gives each plan's terms,
  // and renews is always false: Pro is a one-time payment, never billed again
  // by itself.
  const statusOf = async (userId) => ({
    ...(await proStatus(pool, userId)), prices: PRICES, plans: PLAN_TERMS, renews: false,
  });

  /// Where PayMongo sends the browser back: PUBLIC_BASE_URL when it is a real
  /// address, else the origin the app reached us on -- so the phone hotspot
  /// needs no setting.
  const baseFor = (req) => (publicBaseUrl && !LOCALHOST.test(publicBaseUrl)
    ? publicBaseUrl.replace(/\/+$/, '')
    : `${req.protocol}://${req.get('host')}`);

  /// Asks PayMongo whether [payment] was paid and, if so, adds its period.
  /// Returns 'paid' or 'pending'. Throws PAYMENTS_UNAVAILABLE (502) when
  /// PayMongo can't be asked, PAYMENT_MISMATCH (409) when what was paid is
  /// not our price.
  async function settle(req, payment) {
    if (payment.status === 'paid') return 'paid';
    if (!payment.sessionId || !payments) return 'pending';
    let session;
    try {
      session = await payments.getCheckout(payment.sessionId);
    } catch (err) {
      log(req)?.warn({ paymentId: payment.paymentId, code: err?.code ?? null, status: err?.status ?? null }, 'pro payment check failed');
      throw unavailable(502, CHECK_FAILED);
    }
    if (!session.paid) return 'pending';
    if (session.amountCentavos !== Math.round(payment.amountPhp * 100) || session.currency !== 'PHP') {
      log(req)?.warn({ paymentId: payment.paymentId }, 'pro payment does not match its plan');
      throw AppError.conflict('PAYMENT_MISMATCH', "This payment doesn't match its plan.");
    }
    await completePayment(pool, {
      userId: payment.userId, paymentId: payment.paymentId, months: PLANS[payment.plan].months, method: session.method,
    });
    log(req)?.info({ paymentId: payment.paymentId, plan: payment.plan, method: session.method }, 'pro payment confirmed');
    return 'paid';
  }

  /// A payment the app lost track of -- the screen closed, or the app was
  /// killed, before it asked -- is finished the next time the app asks for
  /// the status. Best effort, at most 3 attempts from the last day, asked in
  /// parallel: PayMongo down or a mismatch leaves an attempt pending (logged
  /// in settle) and the status still answers. A database error is a real
  /// failure and propagates.
  ///
  /// The check gets [checkBudgetMs], well inside the app's 10 s limit: a
  /// PayMongo that hangs rather than fails would otherwise hold the status
  /// for the client's 15 s. Past the budget the status answers as it stands;
  /// the checks run on, and completePayment is transactional and idempotent,
  /// so a late finish is safe and the next read shows it.
  async function settleRecent(req, userId) {
    if (!payments) return;
    const pending = await recentPendingPayments(pool, userId);
    if (pending.length === 0) return;
    const all = Promise.allSettled(pending.map((p) => settle(req, p)));
    let timer;
    const late = new Promise((resolve) => { timer = setTimeout(resolve, checkBudgetMs, null); });
    const results = await Promise.race([all, late]).finally(() => clearTimeout(timer));
    if (!results) {
      log(req)?.warn({ userId, pending: pending.length }, 'pro payment check slow');
      all.then((settled) => {
        const err = settled.find((r) => r.status === 'rejected' && !(r.reason instanceof AppError));
        if (err) log(req)?.error({ userId, code: err.reason?.code ?? null }, 'pro payment check failed late');
      });
      return;
    }
    const broken = results.find((r) => r.status === 'rejected' && !(r.reason instanceof AppError));
    if (broken) throw broken.reason;
  }

  router.get('/', auth, async (req, res, next) => {
    try {
      await settleRecent(req, req.user.userId);
      res.json({ data: await statusOf(req.user.userId) });
    } catch (err) { next(err); }
  });

  router.post('/checkout', auth, async (req, res, next) => {
    try {
      const key = req.body?.plan;
      if (typeof key !== 'string' || !Object.hasOwn(PLANS, key)) {
        throw AppError.badRequest('INVALID_PLAN', 'plan must be monthly or annual.');
      }
      if (!payments) throw unavailable(503, OPEN_FAILED);
      const plan = PLANS[key];
      const paymentId = await createPayment(pool, { userId: req.user.userId, plan: key, amountPhp: plan.pricePhp });
      const base = baseFor(req);
      const back = (result) => `${base}/api/v1/pro/return?payment=${paymentId}&result=${result}`;
      let checkout;
      try {
        checkout = await payments.createCheckout({
          referenceNumber: `fitsync-${paymentId}`,
          name: plan.name,
          amountCentavos: plan.pricePhp * 100,
          successUrl: back('success'),
          cancelUrl: back('cancel'),
          pageBase: base,
        });
      } catch (err) {
        log(req)?.warn({ paymentId, code: err?.code ?? null, status: err?.status ?? null }, 'pro checkout failed');
        throw unavailable(502, OPEN_FAILED);
      }
      await setCheckoutSession(pool, paymentId, checkout.sessionId);
      log(req)?.info({ paymentId, plan: key }, 'pro checkout opened');
      res.status(201).json({ data: { paymentId, checkoutUrl: checkout.checkoutUrl } });
    } catch (err) { next(err); }
  });

  router.post('/payments/:paymentId/confirm', auth, async (req, res, next) => {
    try {
      const { userId } = req.user;
      const paymentId = Number(req.params.paymentId);
      const payment = Number.isInteger(paymentId) && paymentId > 0 ? await findPayment(pool, userId, paymentId) : null;
      if (!payment) throw AppError.notFound('PAYMENT_NOT_FOUND', 'No such payment.');
      const status = await settle(req, payment);
      res.json({ data: { status, pro: await statusOf(userId) } });
    } catch (err) { next(err); }
  });

  // Where PayMongo's page sends the browser after paying or giving up. A
  // courtesy only: the app confirms the payment itself.
  router.get('/return', (req, res) => {
    const paid = req.query.result === 'success';
    res.type('html').send(renderPage(paid
      ? { title: 'Payment received', body: '<p>Go back to FitSync. It confirms your Pro by itself.</p>' }
      : { title: 'Payment not completed', body: '<p>Go back to FitSync to try again or choose another plan.</p>' }));
  });

  // The stub's stand-in for PayMongo's test page (PAYMONGO_MODE=stub only).
  if (payments?.mode === 'stub') {
    // helmet's default policy asks the browser to upgrade requests to https,
    // which breaks this form's POST on a plain-http address that is not
    // localhost (the phone hotspot, the emulator's 10.0.2.2). Same policy,
    // minus that one directive.
    const stubPolicy = helmet.contentSecurityPolicy({ useDefaults: true, directives: { upgradeInsecureRequests: null } });
    router.use('/stub-checkout', stubPolicy);
    router.get('/stub-checkout/:sessionId', (req, res, next) => {
      const s = payments.session(req.params.sessionId);
      if (!s) return next(AppError.notFound('CHECKOUT_NOT_FOUND', 'No such checkout.'));
      const action = escapeHtml(req.params.sessionId);
      const php = (s.amountCentavos / 100).toLocaleString('en-PH');
      res.type('html').send(renderPage({
        title: 'Test checkout',
        body: `<p>${escapeHtml(s.name)}: ₱${escapeHtml(php)}</p>
<p>FitSync's stand-in for PayMongo's test page.</p>
<form method="post" action="${action}"><input type="hidden" name="action" value="authorize"><button type="submit">Authorize</button></form>
<p></p>
<form method="post" action="${action}"><input type="hidden" name="action" value="fail"><button type="submit">Fail</button></form>`,
      }));
    });
    router.post('/stub-checkout/:sessionId', express.urlencoded({ extended: false }), (req, res, next) => {
      const to = payments.complete(req.params.sessionId, req.body?.action);
      if (!to) return next(AppError.notFound('CHECKOUT_NOT_FOUND', 'No such checkout.'));
      res.redirect(303, to);
    });
  }

  return router;
};
