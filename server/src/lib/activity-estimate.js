'use strict';

/// Walking estimates from one day's step count
/// (docs/superpowers/specs/2026-09-28-activity-steps-design.md). kcal is the
/// walking alone -- workouts are never added -- and every figure is an
/// estimate the Activity screen labels as one.

/// Stride as a fraction of height: the common height-based approximation.
const STRIDE_RATIO = Object.freeze({ male: 0.415, female: 0.413 });
const DEFAULT_STRIDE_RATIO = 0.414;

/// ACSM's walking equation, net of resting: 0.1 mL O2 per kg per metre,
/// about 0.5 kcal per kg per km.
const KCAL_PER_KG_KM = 0.5;

/// About 100 steps a minute is the research cadence threshold for moderate
/// walking.
const STEPS_PER_ACTIVE_MINUTE = 100;

/// A positive number from a number or a MySQL DECIMAL string, else null.
function positive(value) {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/// What one step adds to each estimate for this body, unrounded: km walked,
/// kcal burned and active minutes. A factor is null when the profile lacks
/// what it needs (height for distance; height and weight for kcal).
///
/// The week sends these to the app, which grows today's saved figures to the
/// phone's live step count with them. estimateActivity computes through them
/// too, so the app's figure for a step count is exactly the one the server
/// would save for it.
function perStepFactors({ heightCm, weightKg, sex }) {
  const height = positive(heightCm);
  const weight = positive(weightKg);
  const ratio = STRIDE_RATIO[sex] ?? DEFAULT_STRIDE_RATIO;
  const distanceKm = height === null ? null : ((height / 100) * ratio) / 1000;
  return {
    distanceKm,
    caloriesBurned: distanceKm === null || weight === null
      ? null
      : KCAL_PER_KG_KM * weight * distanceKm,
    activeMinutes: 1 / STEPS_PER_ACTIVE_MINUTE,
  };
}

/// One day's estimates: steps times each per-step factor, then rounded --
/// km to two places, kcal and minutes to whole numbers. The app repeats
/// exactly these operations in this order (ActivityDay.grownTo); computing
/// it any other way can land a value sitting on a .5 boundary on the other
/// side of it.
function estimateActivity({ steps, heightCm, weightKg, sex }) {
  const f = perStepFactors({ heightCm, weightKg, sex });
  return {
    distanceKm: f.distanceKm === null ? null : Math.round(steps * f.distanceKm * 100) / 100,
    caloriesBurned: f.caloriesBurned === null ? null : Math.round(steps * f.caloriesBurned),
    activeMinutes: Math.round(steps * f.activeMinutes),
    missing: [
      ...(positive(heightCm) === null ? ['height'] : []),
      ...(positive(weightKg) === null ? ['weight'] : []),
    ],
  };
}

module.exports = { estimateActivity, perStepFactors };
