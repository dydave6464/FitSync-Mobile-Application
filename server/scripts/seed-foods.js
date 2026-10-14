'use strict';
const { load } = require('../src/config');
const { seedFoods } = require('../src/db/seed-foods');

seedFoods(load().db)
  .then((s) => {
    console.log(
      `Seeded foods: ${s.inserted} inserted, ${s.updated} updated, ${s.unchanged} unchanged (of ${s.total} total).`,
    );
    process.exit(0);
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
