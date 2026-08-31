'use strict';
require('dotenv').config();
const { load } = require('../src/config');
const { seedExerciseSafety } = require('../src/db/seed-exercise-safety');

async function main() {
  const config = load();
  const result = await seedExerciseSafety(config.db);
  console.log(
    `requirements: +${result.requirements.inserted} -${result.requirements.removed} `
    + `(${result.requirements.manual} manual)`,
  );
  console.log(
    `contraindications: +${result.contraindications.inserted} -${result.contraindications.removed} `
    + `(${result.contraindications.manual} manual)`,
  );
  if (result.unknownEquipment.length > 0) {
    // Not fatal, but it means some exercises silently kept no requirement.
    console.warn(
      `WARNING: no equipment row for ${result.unknownEquipment.join(', ')}. `
      + 'Run `npm run seed:equipment` first, then re-run this.',
    );
    process.exitCode = 1;
  }
  if (result.unknownRegions.length > 0) {
    // Louder than the equipment case: every dropped row is a safety row.
    console.warn(
      `WARNING: no injury row for ${result.unknownRegions.join(', ')}. `
      + 'Contraindications for those regions were NOT written. '
      + 'Run `npm run seed:injuries` first, then re-run this.',
    );
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
