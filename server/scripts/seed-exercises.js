'use strict';
const { load } = require('../src/config');
const { seedExercises } = require('../src/db/seed-exercises');
const manifest = require('../src/db/seeds/exercises.json');

seedExercises(load().db, manifest)
  .then((summary) => {
    console.log(
      `Seeded ${summary.exercises} exercises, ${summary.equipment} equipment types, `
        + `${summary.cues} cues (${summary.skipped} skipped).`,
    );
    process.exit(0);
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
