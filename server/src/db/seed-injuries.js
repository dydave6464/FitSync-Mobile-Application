'use strict';
const { createPool } = require('./pool');

// Regions, not region-plus-side. "Knee" is a body part; "my right knee" is the
// user's history, recorded as user_injuries.side. Keeping the lookup at 16 rows
// avoids a 40-row cross-product the plan generator would only collapse again.
const REGIONS = [
  { name: 'Shoulder', isLateral: true, regionGroup: 'upper_body' },
  { name: 'Elbow', isLateral: true, regionGroup: 'upper_body' },
  { name: 'Wrist', isLateral: true, regionGroup: 'upper_body' },
  { name: 'Hand', isLateral: true, regionGroup: 'upper_body' },
  { name: 'Neck', isLateral: false, regionGroup: 'back_core' },
  { name: 'Upper back', isLateral: false, regionGroup: 'back_core' },
  { name: 'Lower back', isLateral: false, regionGroup: 'back_core' },
  { name: 'Core', isLateral: false, regionGroup: 'back_core' },
  { name: 'Hip', isLateral: true, regionGroup: 'lower_body' },
  { name: 'Groin', isLateral: true, regionGroup: 'lower_body' },
  { name: 'Hamstring', isLateral: true, regionGroup: 'lower_body' },
  { name: 'Quadriceps', isLateral: true, regionGroup: 'lower_body' },
  { name: 'Knee', isLateral: true, regionGroup: 'lower_body' },
  { name: 'Calf', isLateral: true, regionGroup: 'lower_body' },
  { name: 'Ankle', isLateral: true, regionGroup: 'lower_body' },
  { name: 'Foot', isLateral: true, regionGroup: 'lower_body' },
];

async function seedInjuries(dbConfig) {
  const pool = createPool(dbConfig);
  try {
    for (const r of REGIONS) {
      // uq_injuries_name makes this idempotent without a pre-read.
      await pool.query(
        `INSERT INTO injuries (name, is_lateral, region_group) VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE is_lateral = VALUES(is_lateral),
                                 region_group = VALUES(region_group)`,
        [r.name, r.isLateral, r.regionGroup],
      );
    }
    return { inserted: REGIONS.length };
  } finally {
    await pool.end();
  }
}

module.exports = { seedInjuries, REGIONS };
