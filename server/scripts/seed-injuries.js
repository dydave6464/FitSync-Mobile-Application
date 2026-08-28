'use strict';
const { load } = require('../src/config');
const { seedInjuries } = require('../src/db/seed-injuries');

seedInjuries(load().db)
  .then((summary) => {
    console.log(
      `Seeded injury regions: ${summary.inserted} inserted, ${summary.updated} updated, `
        + `${summary.unchanged} unchanged (of ${summary.total} total).`,
    );
    process.exit(0);
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
