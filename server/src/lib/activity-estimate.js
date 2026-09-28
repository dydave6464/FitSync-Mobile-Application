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

function estimateActivity({ steps, heightCm, weightKg, sex }) {
  const height = positive(heightCm);
  const weight = positive(weightKg);
  const ratio = STRIDE_RATIO[sex] ?? DEFAULT_STRIDE_RATIO;
  const metres = height === null ? null : steps * (height / 100) * ratio;
  return {
    distanceKm: metres === null ? null : Math.round(metres / 10) / 100,
    caloriesBurned: metres === null || weight === null
      ? null
      : Math.round(KCAL_PER_KG_KM * weight * (metres / 1000)),
    activeMinutes: Math.round(steps / STEPS_PER_ACTIVE_MINUTE),
    missing: [
      ...(height === null ? ['height'] : []),
      ...(weight === null ? ['weight'] : []),
    ],
  };
}

module.exports = { estimateActivity };
