'use strict';

// Body-weight exercises only: the stub ignores the user's equipment
// entirely, so a body-weight starter plan is valid regardless of what any
// given user owns. Verified against the live catalogue (see Task 9's
// Step 1 check) — all four resolve.
const DEFAULT_EXERCISES = [
  { name: 'walking lunge', orderNo: 1, targetSets: 3, targetReps: '8-12' },
  { name: 'push-up', orderNo: 2, targetSets: 3, targetReps: '8-12' },
  { name: 'inverted row', orderNo: 3, targetSets: 3, targetReps: '8-12' },
  { name: 'low glute bridge on floor', orderNo: 4, targetSets: 3, targetReps: '10-15' },
];

const SPLIT_DAYS = {
  full_body: 1,
  push_pull_legs: 3,
  upper_lower: 2,
  cardio_core: 1,
};

async function generatePlan(profile = {}) {
  // `overrides` is how a chosen split arrives -- /plans/regenerate sends
  // { ...profile, overrides }, and complete-onboarding sends a bare profile
  // with none, which is why an absent overrides object defaults every field
  // below rather than throwing.
  const overrides = profile.overrides || {};
  const splitStyle = overrides.splitStyle || 'full_body';
  const rotation = SPLIT_DAYS[splitStyle] || 1;

  // Every day gets the same four body-weight exercises. The stub is a
  // placeholder for a generator, not a generator: what it must get right is
  // the SHAPE -- a rotation of the requested length, order restarting per
  // day -- so the routes above it can be exercised without the ML service.
  const exercises = [];
  for (let dayNo = 1; dayNo <= rotation; dayNo += 1) {
    DEFAULT_EXERCISES.forEach((ex, index) => {
      exercises.push({ ...ex, dayNo, orderNo: index + 1 });
    });
  }

  return {
    name: 'Starter Plan',
    splitStyle,
    daysPerWeek: overrides.daysPerWeek || 3,
    sessionLengthMin: overrides.sessionLengthMin || 45,
    weekNo: 1,
    exercises,
  };
}

async function estimateInjuryRisk() {
  // C-6: accuracy is bounded by user input, so the stub reports the
  // conservative floor rather than inventing a risk signal.
  return { riskLevel: 'low', trainingLoadScore: 0 };
}

module.exports = { generatePlan, estimateInjuryRisk };
