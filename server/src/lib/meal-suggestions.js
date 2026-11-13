'use strict';

/// View Local Filipino Meal Suggestions (spec 2026-11-09): up to nine
/// Filipino dishes for the next meal that fit what is left of today's target.
/// Plain rules, no AI and no database -- the route reads, this decides -- so
/// every rule is tested here on fixed numbers.

const MAIN_MEALS = ['breakfast', 'lunch', 'dinner'];
const TOP = 9;
/// Fewer plates than this that fit, and dropped dishes come back without
/// their rice (rule 6).
const FALLBACK_BELOW = 3;
/// Under this many kcal left, today's calories count as reached (rule 2).
const REACHED_BELOW_KCAL = 100;
/// A snack's share: at most 250 kcal and 10 g protein (rule 3).
const SNACK_KCAL = 250;
const SNACK_PROTEIN_G = 10;
/// The light options once the day is reached: snacks of 100 kcal or less (rule 9).
const LIGHT_MAX_KCAL = 100;
/// High protein: protein brings 30% of the plate's calories or more (rule 11).
const HIGH_PROTEIN_SHARE = 0.3;
const DAY_MS = 24 * 60 * 60 * 1000;

const round1 = (n) => Math.round(n * 10) / 10;

/// Days since 1970-01-01 of a 'YYYY-MM-DD' Manila date.
function dayNumber(date) {
  const [y, m, d] = date.split('-').map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / DAY_MS);
}

/// The tie-break (rule 7): equal scores are ordered by this, which moves with
/// the date, so the same three do not lead every day.
const rotation = (foodId, day) => (foodId * 31 + day) % 997;

/// [rice] (one cup) for [cups] cups: its numbers scaled, and how many.
function riceFor(rice, cups) {
  return {
    ...rice,
    servings: cups,
    kcal: Number(rice.kcal) * cups,
    proteinG: Number(rice.proteinG) * cups,
    carbsG: Number(rice.carbsG) * cups,
    fatG: Number(rice.fatG) * cups,
  };
}

/// [dish] at one serving, with [cups] cups of [rice] when given and cups > 0.
/// [servedWithRice] is what the app needs to offer rice on it (spec
/// 2026-11-13, 2.3): true also when the plate came without its rice.
function plateOf(dish, rice, cups = 1, servedWithRice = false) {
  const portion = rice && cups > 0 ? riceFor(rice, cups) : null;
  const items = portion ? [dish, portion] : [dish];
  const sum = (key) => items.reduce((total, f) => total + Number(f[key]), 0);
  return {
    dish, rice: portion, servedWithRice, kcal: sum('kcal'), proteinG: sum('proteinG'), carbsG: sum('carbsG'), fatG: sum('fatG'),
  };
}

/// This meal's part of what is left (rule 3). A main meal shares it with the
/// main meals still to come today that have nothing logged; a snack takes a
/// snack's size, or what is left if that is less.
function shareFor(meal, remainingKcal, remainingProtein, entries) {
  if (meal === 'snack') {
    return { kcal: Math.min(SNACK_KCAL, remainingKcal), proteinG: Math.min(SNACK_PROTEIN_G, remainingProtein) };
  }
  const eaten = new Set(entries.map((e) => e.mealType));
  const n = MAIN_MEALS.slice(MAIN_MEALS.indexOf(meal)).filter((m) => m === meal || !eaten.has(m)).length;
  return { kcal: remainingKcal / n, proteinG: remainingProtein / n };
}

/// Rule 7, lower is better, to 2 decimals (as a whole number of hundredths,
/// so equal-looking scores compare equal): how far the plate is from the
/// share, less up to 0.5 for its protein.
function scoreOf(plate, share) {
  const distance = Math.abs(plate.kcal - share.kcal) / share.kcal;
  const protein = share.proteinG > 0 ? 0.5 * Math.min(plate.proteinG / share.proteinG, 1) : 0;
  return Math.round((distance - protein) * 100);
}

const macrosOf = (x) => ({
  kcal: Math.round(Number(x.kcal)),
  proteinG: round1(Number(x.proteinG)),
  carbsG: round1(Number(x.carbsG)),
  fatG: round1(Number(x.fatG)),
});
const foodOf = (f) => ({ foodId: f.foodId, name: f.name, servingDesc: f.servingDesc, ...macrosOf(f) });

/// A plate as GET /nutrition/suggestions answers it.
function asSuggestion(plate) {
  return {
    food: foodOf(plate.dish),
    rice: plate.rice ? { ...foodOf(plate.rice), servings: plate.rice.servings } : null,
    total: macrosOf(plate),
    servedWithRice: plate.servedWithRice,
    highProtein: plate.kcal > 0 && (plate.proteinG * 4) / plate.kcal >= HIGH_PROTEIN_SHARE,
  };
}

/// White rice, one cup, as the response's riceFood; null without rice.
const asRiceFood = (rice) => (rice ? foodOf(rice) : null);

/// The suggestions for [meal] on [date] (today, Manila).
///
/// [target]: { kcal, proteinG } from dailyTarget, or null when the profile is
/// missing fields. [totals]: today's { kcal, proteinG } so far. [entries]:
/// today's entries ({ mealType, foodId }). [pool]: every visible suggested
/// food, { foodId, name, servingDesc, kcal, proteinG, carbsG, fatG, meals,
/// withRice }. [rice]: the visible "White rice" food, or null.
/// [riceCups]: the user's usual cups of rice (0–2 in halves, 1 if unknown).
/// [yesterday]: yesterday's entries ({ foodId }).
///
/// Returns { state, share, suggestions }: state 'fits', 'no_target' or
/// 'reached'; share { kcal, proteinG } in 'fits' only, else null.
function pickSuggestions({ meal, date, target, totals, entries, pool, rice, riceCups = 1, yesterday = [] }) {
  const day = dayNumber(date);
  // Rule 5: nothing already logged today, at any meal.
  const logged = new Set(entries.map((e) => e.foodId).filter((id) => id != null));
  const fresh = pool.filter((dish) => !logged.has(dish.foodId));
  const forMeal = fresh.filter((dish) => dish.meals.includes(meal));
  const main = MAIN_MEALS.includes(meal);
  // Rule 5b: yesterday's dishes are not dropped, only put after the rest.
  const eatenYesterday = new Set(yesterday.map((e) => e.foodId).filter((id) => id != null));
  const later = (p) => (eatenYesterday.has(p.dish.foodId) ? 1 : 0);
  // Rule 4: ulam with the user's usual rice on a main meal, for a dish
  // served with rice.
  const servedWithRice = (dish) => main && dish.withRice && rice != null;
  const plate = (dish) => plateOf(dish, servedWithRice(dish) ? rice : null, riceCups, servedWithRice(dish));
  const byRotation = (a, b) => rotation(a.dish.foodId, day) - rotation(b.dish.foodId, day);

  // Rule 8: no target to fit, so the most protein for the calories first.
  if (!target) {
    const proteinShare = (p) => (p.kcal > 0 ? (p.proteinG * 4) / p.kcal : 0);
    const plates = forMeal.map(plate)
      .sort((a, b) => later(a) - later(b) || proteinShare(b) - proteinShare(a) || byRotation(a, b));
    return { state: 'no_target', share: null, suggestions: plates.slice(0, TOP).map(asSuggestion) };
  }

  // Rule 1.
  const remainingKcal = target.kcal - totals.kcal;
  const remainingProtein = Math.max(0, target.proteinG - totals.proteinG);

  // Rule 9: the day is reached, so light snacks only, never with rice,
  // whatever the meal.
  if (remainingKcal < REACHED_BELOW_KCAL) {
    const light = fresh
      .filter((dish) => dish.meals.includes('snack') && Number(dish.kcal) <= LIGHT_MAX_KCAL)
      .map((dish) => plateOf(dish, null))
      .sort((a, b) => later(a) - later(b) || b.proteinG - a.proteinG || a.kcal - b.kcal || byRotation(a, b));
    return { state: 'reached', share: null, suggestions: light.slice(0, TOP).map(asSuggestion) };
  }

  const share = shareFor(meal, remainingKcal, remainingProtein, entries);
  const ranked = (plates) => plates
    .map((p) => ({ ...p, score: scoreOf(p, share) }))
    .sort((a, b) => later(a) - later(b) || a.score - b.score || byRotation(a, b));

  // Rule 6: plates over what is left are dropped. Short of three, the
  // dropped dishes come back without their rice where the dish alone fits.
  const fitting = ranked(forMeal.map(plate).filter((p) => p.kcal <= remainingKcal));
  let picked = fitting;
  if (fitting.length < FALLBACK_BELOW) {
    const kept = new Set(fitting.map((p) => p.dish.foodId));
    const alone = ranked(forMeal
      .filter((dish) => !kept.has(dish.foodId))
      .map((dish) => plateOf(dish, null, riceCups, servedWithRice(dish)))
      .filter((p) => p.kcal <= remainingKcal));
    picked = ranked([...fitting, ...alone.slice(0, FALLBACK_BELOW - fitting.length)]);
  }
  return {
    state: 'fits',
    share: { kcal: Math.round(share.kcal), proteinG: round1(share.proteinG) },
    suggestions: picked.slice(0, TOP).map(asSuggestion),
  };
}

module.exports = { pickSuggestions, dayNumber, asRiceFood };
