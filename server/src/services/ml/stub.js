'use strict';

const DEFAULT_EXERCISES = [
  { name: 'Goblet Squat', orderNo: 1, targetSets: 3, targetReps: '8-12' },
  { name: 'Push-Up', orderNo: 2, targetSets: 3, targetReps: '8-12' },
  { name: 'Dumbbell Row', orderNo: 3, targetSets: 3, targetReps: '8-12' },
  { name: 'Glute Bridge', orderNo: 4, targetSets: 3, targetReps: '10-15' },
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
