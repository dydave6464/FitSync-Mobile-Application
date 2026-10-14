'use strict';

/// The daily calorie and macro target the food log measures against.
///
/// Maintenance is the same Mifflin-St Jeor estimate the app's onboarding
/// shows (client/lib/features/onboarding/domain/daily_targets.dart), rounded
/// the same way, so the two agree about the same person. A shared fixture
/// (tests/fixtures/daily-targets-parity.json) holds them together. The
/// onboarding estimate has no calorie floor, so with no goal adjustment the
/// two agree only when maintenance is at or above the floor below.

const SEX_CONSTANTS = { male: 5, female: -161 };
const MULTIPLIERS = {
  sedentary: 1.2, light: 1.375, moderate: 1.55, active: 1.725, very_active: 1.9,
};
// The focus goal (users.main_goal). Unknown or null: maintenance.
const GOAL_ADJUST = { lose_weight: -500, build_muscle: 250 };
// Common minimums for an unsupervised diet.
const FLOORS = { female: 1200, male: 1500 };
const PROTEIN_PER_KG = 1.6;
const FAT_SHARE = 0.25;

function ageOn(dateOfBirth, today) {
  const [by, bm, bd] = dateOfBirth.split('-').map(Number);
  const [ty, tm, td] = today.split('-').map(Number);
  let age = ty - by;
  if (tm < bm || (tm === bm && td < bd)) age -= 1;
  return age;
}

function missingFields(p) {
  const missing = [];
  if (!(p.sex in SEX_CONSTANTS)) missing.push('sex');
  if (!p.dateOfBirth) missing.push('dateOfBirth');
  if (!(Number(p.heightCm) > 0)) missing.push('heightCm');
  if (!(Number(p.weightKg) > 0)) missing.push('weightKg');
  if (!(p.activityLevel in MULTIPLIERS)) missing.push('activityLevel');
  return missing;
}

function dailyTarget(profile, today) {
  const missing = missingFields(profile);
  if (missing.length > 0) return { target: null, missing };

  const weightKg = Number(profile.weightKg);
  const heightCm = Number(profile.heightCm);
  const bmr = 10 * weightKg + 6.25 * heightCm
    - 5 * ageOn(profile.dateOfBirth, today) + SEX_CONSTANTS[profile.sex];
  const maintenance = Math.round((bmr * MULTIPLIERS[profile.activityLevel]) / 50) * 50;
  const kcal = Math.max(FLOORS[profile.sex], maintenance + (GOAL_ADJUST[profile.mainGoal] || 0));
  const proteinG = Math.round((weightKg * PROTEIN_PER_KG) / 5) * 5;
  const fatG = Math.round((kcal * FAT_SHARE) / 9);
  const carbsG = Math.max(0, Math.round((kcal - 4 * proteinG - 9 * fatG) / 4));
  return { target: { kcal, proteinG, carbsG, fatG }, missing: [] };
}

module.exports = { dailyTarget, ageOn };
