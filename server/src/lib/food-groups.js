'use strict';

/// The food groups a dish can contain and a trainee can avoid (Meal ideas
/// round 2, spec 2026-11-13). The order is the SET columns' order
/// (foods.contains, users.avoid_foods, migrations 050/051) and the app's.
const FOOD_GROUPS = ['pork', 'beef', 'chicken', 'fish', 'shellfish', 'egg'];

module.exports = { FOOD_GROUPS };
