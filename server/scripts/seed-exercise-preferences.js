'use strict';
const { load } = require('../src/config');
const { seedExercisePreferences, nothingMatched } = require('../src/db/seed-exercise-preferences');

seedExercisePreferences(load().db)
  .then((s) => {
    console.log(
      `Seeded exercise preferences: ${s.inserted} inserted, ${s.updated} updated, ${s.unchanged} unchanged, `
      + `${s.manual} manual, ${s.skippedUnknown} not in the catalogue (of ${s.total} total).`,
    );
    const failure = nothingMatched(s);
    if (failure) {
      console.error(failure);
      process.exit(1);
    }
    process.exit(0);
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
