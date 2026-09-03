'use strict';
require('dotenv').config();
const { load } = require('../src/config');
const { seedExerciseCategories } = require('../src/db/seed-exercise-categories');

async function main() {
  const config = load();
  const result = await seedExerciseCategories(config.db);
  console.log(`categories: +${result.inserted} -${result.removed} (${result.manual} manual)`);
  const { strength, stretch, mobility, other } = result.counts;
  console.log(`  strength ${strength}  stretch ${stretch}  mobility ${mobility}  other ${other}`);
}

main().catch((err) => { console.error(err); process.exit(1); });
