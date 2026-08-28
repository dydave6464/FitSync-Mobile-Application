'use strict';
const express = require('express');
const AppError = require('../lib/app-error');
const requireAuth = require('../middleware/require-auth');
const {
  getProfile, updateProfile, setEquipment, setInjuries,
  listEquipment, listInjuries, markOnboardingComplete, WRITABLE,
} = require('../db/profile');
const { savePlan, getActivePlan } = require('../db/plans');

const ENUMS = {
  sex: ['male', 'female', 'prefer_not_to_say'],
  mainGoal: ['lose_weight', 'build_muscle', 'improve_endurance', 'general_fitness'],
  fitnessLevel: ['beginner', 'intermediate'],
  activityLevel: ['sedentary', 'light', 'moderate', 'active', 'very_active'],
  trainingLocation: ['home_gym', 'commercial_gym', 'both', 'other'],
};
const NUMERIC = ['heightCm', 'weightKg', 'goalWeightKg'];
const SIDES = ['left', 'right', 'both'];

// users.full_name and users.notifications_enabled are NOT NULL. Every other
// WRITABLE column allows NULL, and clearing an optional field is legitimate.
const REQUIRED_NOT_NULL = ['fullName', 'notificationsEnabled'];

// Both columns are VARCHAR(255). An over-length string must be rejected here,
// not discovered as ER_DATA_TOO_LONG from the database.
const MAX_LENGTH = { fullName: 255, city: 255 };

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

    if (value === null) {
      if (REQUIRED_NOT_NULL.includes(key)) {
        throw invalid(key, `${key} cannot be null.`);
      }
      fields[key] = null;
      continue;
    }

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
    if (MAX_LENGTH[key] && typeof value === 'string' && value.length > MAX_LENGTH[key]) {
      throw invalid(key, `${key} must be at most ${MAX_LENGTH[key]} characters.`);
    }
    fields[key] = value;
  }
  return fields;
}

function validateIds(name, raw) {
  if (!Array.isArray(raw)) throw invalid(name, `${name} must be an array.`);
  const ids = raw.map((v) => {
    const n = Number(v);
    if (!Number.isSafeInteger(n) || n < 1) throw invalid(name, `${name} must contain positive integers.`);
    return n;
  });
  if (new Set(ids).size !== ids.length) {
    throw invalid(name, `${name} must not contain duplicate ids.`);
  }
  return ids;
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
      // A stale cached list on the client can name equipment that no longer
      // exists. Checking here turns that into a 400 instead of the FK
      // violation (ER_NO_REFERENCED_ROW_2) that setEquipment's insert would
      // otherwise raise as an opaque 500.
      if (ids.length > 0) {
        const [rows] = await pool.query(
          'SELECT equipment_id FROM equipment WHERE equipment_id IN (?)', [ids],
        );
        if (rows.length !== ids.length) {
          throw invalid('equipmentIds', 'equipmentIds must reference existing equipment.');
        }
      }
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

      const ids = entries.map((e) => e.injuryId);
      if (new Set(ids).size !== ids.length) {
        throw invalid('injuries', 'injuries must not contain duplicate injuryId values.');
      }

      // One lookup answers both remaining questions: does this injuryId
      // exist (the same FK-violation-as-500 risk equipment has), and is a
      // non-null side meaningful for it. injuries.is_lateral exists
      // precisely so a side can be rejected on a region that has none, e.g.
      // Neck — silently accepting it would feed Module 2's plan generation
      // with meaningless laterality.
      if (entries.length > 0) {
        const [rows] = await pool.query(
          'SELECT injury_id, is_lateral FROM injuries WHERE injury_id IN (?)', [ids],
        );
        const lateralById = new Map(rows.map((r) => [r.injury_id, Boolean(r.is_lateral)]));
        for (const entry of entries) {
          if (!lateralById.has(entry.injuryId)) {
            throw invalid('injuries', 'injuries must reference an existing injury.');
          }
          if (entry.side !== null && !lateralById.get(entry.injuryId)) {
            throw invalid('injuries', 'side is not applicable to a non-lateral injury.');
          }
        }
      }

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

  router.post('/profile/complete-onboarding', auth, async (req, res, next) => {
    try {
      const userId = req.user.userId;
      const profile = await getProfile(pool, userId);

      // Generate first, mark complete second. If generation throws, the user
      // stays mid-onboarding and can retry — rather than being "done" with no plan.
      const generated = await deps.ml.generatePlan(profile);
      await savePlan(pool, userId, generated);
      await markOnboardingComplete(pool, userId);

      res.json({
        data: {
          profile: await getProfile(pool, userId),
          plan: await getActivePlan(pool, userId),
        },
      });
    } catch (err) { next(err); }
  });

  return router;
};
