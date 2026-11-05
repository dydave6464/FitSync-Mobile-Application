'use strict';
const AppError = require('./app-error');
const { manilaDay } = require('./manila-day');

/// What a food log request may contain, checked the one way every log route
/// checks it (POST /nutrition/entries, PATCH /nutrition/entries/:id, and
/// Snap a meal's POST /nutrition/recognitions/:id/log).
const MAX_SERVINGS = 20;
const MAX_GRAMS = 500;
const MAX_SODIUM_MG = 20000;
const MAX_NAME = 100;
const MAX_SERVING_DESC = 60;
const round1 = (n) => Math.round(n * 10) / 10;
const round2 = (n) => Math.round(n * 100) / 100;

function invalid(field, message) {
  return AppError.badRequest('INVALID_NUTRITION_FIELD', message, [{ field }]);
}

/// A real calendar date, not after today in Manila. Undefined -> today.
function checkDate(value) {
  const today = manilaDay();
  if (value === undefined) return today;
  // A month or day out of range (2026-13-01) parses to an Invalid Date, whose
  // toISOString() throws; February 30th parses, rolls over, and fails the compare.
  const d = typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) ? new Date(`${value}T00:00:00Z`) : null;
  const ok = d !== null && !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
  if (!ok) throw AppError.badRequest('INVALID_DATE', 'date must be a real date as YYYY-MM-DD.');
  if (value > today) throw AppError.badRequest('INVALID_DATE', 'date cannot be in the future.');
  return value;
}

function checkServings(s) {
  if (typeof s !== 'number' || !Number.isFinite(s) || s < 0.5 || s > MAX_SERVINGS || !Number.isInteger(s * 2)) {
    throw invalid('servings', `servings must be 0.5 to ${MAX_SERVINGS}, in steps of 0.5.`);
  }
  return s;
}

/// An optional manual value: absent or null is unknown (null); otherwise a
/// number from 0 to [max]. Never part of kcal.
function optional(food, key, max, round) {
  const v = food[key];
  if (v == null) return null;
  if (typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > max) {
    throw invalid(key, `${key} must be 0 to ${max}.`);
  }
  return round(v);
}

/// A manual food's per-serving numbers. kcal is 4-4-9 from protein, carbs and
/// fat -- unless [basedOn], the per-serving numbers it was edited from (a
/// listed food, or the entry being edited), has the same protein, carbs and
/// fat: then that kcal is kept, since it may count what 4-4-9 can't (a beer's
/// alcohol), and 0/0/0 is fine when it is above 0. Never a kcal from the app.
function checkManual(food, { basedOn = null } = {}) {
  const name = typeof food.name === 'string' ? food.name.trim() : '';
  if (name.length < 1 || name.length > MAX_NAME) throw invalid('name', `name must be 1 to ${MAX_NAME} characters.`);
  let servingDesc = null;
  if (food.servingDesc != null) {
    if (typeof food.servingDesc !== 'string') throw invalid('servingDesc', 'servingDesc must be text.');
    servingDesc = food.servingDesc.trim() || null;
    if (servingDesc && servingDesc.length > MAX_SERVING_DESC) {
      throw invalid('servingDesc', `servingDesc must be at most ${MAX_SERVING_DESC} characters.`);
    }
  }
  const grams = {};
  for (const k of ['proteinG', 'carbsG', 'fatG']) {
    const g = food[k];
    if (typeof g !== 'number' || !Number.isFinite(g) || g < 0 || g > MAX_GRAMS) {
      throw invalid(k, `${k} must be 0 to ${MAX_GRAMS}.`);
    }
    grams[k] = round2(g);
  }
  const listed = basedOn !== null && ['proteinG', 'carbsG', 'fatG'].every((k) => round2(basedOn[k]) === grams[k]);
  if (grams.proteinG + grams.carbsG + grams.fatG === 0 && !(listed && basedOn.kcal > 0)) {
    throw invalid('food', 'A manual food needs some protein, carbs or fat.');
  }
  const kcal = listed ? basedOn.kcal : Math.round(4 * grams.proteinG + 4 * grams.carbsG + 9 * grams.fatG);
  const fiberG = optional(food, 'fiberG', MAX_GRAMS, round2);
  const sugarG = optional(food, 'sugarG', MAX_GRAMS, round2);
  const sodiumMg = optional(food, 'sodiumMg', MAX_SODIUM_MG, round1);
  return { name, servingDesc, kcal, fiberG, sugarG, sodiumMg, ...grams };
}

/// Per-serving numbers [base] times [servings], rounded the one way every
/// stored entry is: kcal whole, grams to 2 places, sodium to 1; null stays null.
function scaled(base, servings) {
  return {
    kcal: Math.round(base.kcal * servings),
    proteinG: round2(base.proteinG * servings),
    carbsG: round2(base.carbsG * servings),
    fatG: round2(base.fatG * servings),
    fiberG: base.fiberG == null ? null : round2(base.fiberG * servings),
    sugarG: base.sugarG == null ? null : round2(base.sugarG * servings),
    sodiumMg: base.sodiumMg == null ? null : round1(base.sodiumMg * servings),
  };
}

module.exports = { invalid, checkDate, checkServings, checkManual, scaled, round1, round2 };
