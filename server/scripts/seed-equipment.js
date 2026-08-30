'use strict';
const { load } = require('../src/config');
const { seedEquipment } = require('../src/db/seed-equipment');

seedEquipment(load().db)
  .then((summary) => {
    console.log(
      `Seeded equipment options: ${summary.inserted} inserted, ${summary.updated} updated, `
        + `${summary.unchanged} unchanged (of ${summary.total} total), `
        + `${summary.adopted} catalogue tags absorbed. `
        + `Selections: ${summary.movedSelections} moved to a parent, `
        + `${summary.droppedSelections} dropped.`,
    );
    process.exit(0);
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
