'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const requireAuth = require('../middleware/require-auth');
const {
  getProfile, updateProfile, setEquipment, setInjuries,
  listEquipment, listInjuries, WRITABLE,
} = require('../db/profile');

const ENUMS = {
  sex: ['male', 'female', 'prefer_not_to_say'],
  mainGoal: ['lose_weight', 'build_muscle', 'improve_endurance', 'general_fitness'],
  fitnessLevel: ['beginner', 'intermediate'],
  activityLevel: ['sedentary', 'light', 'moderate', 'active', 'very_active'],
  trainingLocation: ['home_gym', 'commercial_gym', 'both', 'other'],
};
const NUMERIC = ['heightCm', 'weightKg', 'goalWeightKg'];
const SIDES = ['left', 'right', 'both'];

function invalid(field, message) {
  return AppError.badRequest('INVALID_PROFILE_FIELD', message, [{ field }]);
}

// Silently dropping unknown keys is deliberate: the client may send a whole
// form back. What must never happen is a key outside WRITABLE reaching SQL.
function validatePatch(body) {
  const fields = {};
  for (const key of Object.keys(WRITABLE)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    const value = body[key];

    if (value === null) { fields[key] = null; continue; }

    if (ENUMS[key] && !ENUMS[key].includes(value)) {
      throw invalid(key, `${key} must be one of: ${ENUMS[key].join(', ')}.`);
    }
    if (NUMERIC.includes(key)) {
      const n = Number(value);
      if (!Number.isFinite(n) || n <= 0 || n >= 1000) {
        throw invalid(key, `${key} must be a number between 0 and 1000.`);
      }
      fields[key] = n;
      continue;
    }
    if (key === 'notificationsEnabled') {
      if (typeof value !== 'boolean') throw invalid(key, 'notificationsEnabled must be a boolean.');
      fields[key] = value;
      continue;
    }
    if (key === 'dateOfBirth' && !/^\d{4}-\d{2}-\d{2}$/.test(String(value))) {
      throw invalid(key, 'dateOfBirth must be YYYY-MM-DD.');
    }
    fields[key] = value;
  }
  return fields;
}

function validateIds(name, raw) {
  if (!Array.isArray(raw)) throw invalid(name, `${name} must be an array.`);
  return raw.map((v) => {
    const n = Number(v);
    if (!Number.isSafeInteger(n) || n < 1) throw invalid(name, `${name} must contain positive integers.`);
    return n;
  });
}

module.exports = function buildProfileRouter(deps) {
  const { pool } = deps;
  const router = express.Router();
  const auth = requireAuth(deps);

  const respond = async (res, userId) =>
    res.json({ data: { profile: await getProfile(pool, userId) } });

  router.get('/profile', auth, async (req, res, next) => {
    try { await respond(res, req.user.userId); } catch (err) { next(err); }
  });

  router.patch('/profile', auth, async (req, res, next) => {
    try {
      await updateProfile(pool, req.user.userId, validatePatch(req.body || {}));
      await respond(res, req.user.userId);
    } catch (err) { next(err); }
  });

  router.put('/profile/equipment', auth, async (req, res, next) => {
    try {
      const ids = validateIds('equipmentIds', (req.body || {}).equipmentIds);
      await setEquipment(pool, req.user.userId, ids);
      await respond(res, req.user.userId);
    } catch (err) { next(err); }
  });

  router.put('/profile/injuries', auth, async (req, res, next) => {
    try {
      const raw = (req.body || {}).injuries;
      if (!Array.isArray(raw)) throw invalid('injuries', 'injuries must be an array.');
      const entries = raw.map((entry) => {
        const injuryId = Number(entry && entry.injuryId);
        if (!Number.isSafeInteger(injuryId) || injuryId < 1) {
          throw invalid('injuries', 'each entry needs a positive injuryId.');
        }
        const side = entry.side === undefined || entry.side === null ? null : entry.side;
        if (side !== null && !SIDES.includes(side)) {
          throw invalid('injuries', `side must be one of: ${SIDES.join(', ')}.`);
        }
        return { injuryId, side };
      });
      await setInjuries(pool, req.user.userId, entries);
      await respond(res, req.user.userId);
    } catch (err) { next(err); }
  });

  router.get('/equipment', auth, async (_req, res, next) => {
    try { res.json({ data: { equipment: await listEquipment(pool) } }); } catch (err) { next(err); }
  });

  router.get('/injuries', auth, async (_req, res, next) => {
    try { res.json({ data: { injuries: await listInjuries(pool) } }); } catch (err) { next(err); }
  });

  return router;
};
