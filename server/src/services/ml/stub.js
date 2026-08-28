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

async function generatePlan(profile = {}) {
  return {
    name: 'Starter Plan',
    splitStyle: profile.splitStyle || 'full_body',
    daysPerWeek: profile.daysPerWeek || 3,
    sessionLengthMin: profile.sessionLengthMin || 45,
    weekNo: 1,
    exercises: DEFAULT_EXERCISES.map((ex) => ({ ...ex })),
  };
}

async function estimateInjuryRisk() {
  // C-6: accuracy is bounded by user input, so the stub reports the
  // conservative floor rather than inventing a risk signal.
  return { riskLevel: 'low', trainingLoadScore: 0 };
}

module.exports = { generatePlan, estimateInjuryRisk };
