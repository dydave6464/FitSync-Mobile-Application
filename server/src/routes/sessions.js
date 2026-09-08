'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const {
  getActiveSession,
  startSession,
  completeSession,
  abandonSession,
} = require('../db/sessions');

/// A non-numeric id reaches MySQL as a bare NaN token and throws
/// ER_BAD_FIELD_ERROR -- not an AppError, so it would surface as a 500. Reject
/// it here as the same 404 the "not found / not yours" branch uses, exactly as
/// routes/plans.js does for plan exercise ids.
function sessionIdOr404(raw) {
  const id = Number.parseInt(raw, 10);
  if (!Number.isInteger(id)) {
    throw AppError.notFound('SESSION_NOT_FOUND', 'No such session.');
  }
  return id;
}

const notFound = () => AppError.notFound('SESSION_NOT_FOUND', 'No such session.');

module.exports = function buildSessionsRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);

  router.get('/active', auth, async (req, res, next) => {
    try {
      // Null rather than 404: having no session in progress is the normal
      // state, the same contract GET /plans/active states.
      res.json({ data: { session: await getActiveSession(deps.pool, req.user.userId) } });
    } catch (err) { next(err); }
  });

  router.post('/', auth, async (req, res, next) => {
    try {
      const { session, created } = await startSession(deps.pool, req.user.userId);
      res.status(created ? 201 : 200).json({ data: { session } });
    } catch (err) { next(err); }
  });

  router.post('/:sessionId/complete', auth, async (req, res, next) => {
    try {
      const id = sessionIdOr404(req.params.sessionId);

      const durationMin = Number.parseInt(req.body?.durationMin, 10);
      if (!Number.isInteger(durationMin) || durationMin < 0 || durationMin > 1440) {
        throw AppError.badRequest(
          'DURATION_INVALID',
          'durationMin must be a whole number of minutes between 0 and 1440.',
        );
      }

      const session = await completeSession(deps.pool, req.user.userId, id, durationMin);
      if (!session) throw notFound();
      res.json({ data: { session } });
    } catch (err) { next(err); }
  });

  router.post('/:sessionId/abandon', auth, async (req, res, next) => {
    try {
      const id = sessionIdOr404(req.params.sessionId);
      const ok = await abandonSession(deps.pool, req.user.userId, id);
      if (!ok) throw notFound();
      res.json({ data: { abandoned: true } });
    } catch (err) { next(err); }
  });

  return router;
};
