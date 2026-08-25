'use strict';
const { load } = require('../../src/config');

function testDbConfig() {
  const cfg = load();
  return { ...cfg.db, database: `${cfg.db.database}_test` };
}

async function dropAllTables(pool) {
  const cfg = testDbConfig();
  const [rows] = await pool.query(
    'SELECT table_name AS t FROM information_schema.tables WHERE table_schema = ?',
    [cfg.database],
  );
  if (rows.length === 0) return;

  const conn = await pool.getConnection();
  try {
    await conn.query('SET FOREIGN_KEY_CHECKS = 0');
    for (const row of rows) {
      await conn.query(`DROP TABLE IF EXISTS \`${row.t}\``);
    }
  } finally {
    await conn.query('SET FOREIGN_KEY_CHECKS = 1').catch(() => {});
    conn.release();
  }
}

async function tableNames(pool) {
  const cfg = testDbConfig();
  const [rows] = await pool.query(
    'SELECT table_name AS t FROM information_schema.tables WHERE table_schema = ? ORDER BY table_name',
    [cfg.database],
  );
  return rows.map((r) => r.t);
}

module.exports = { testDbConfig, dropAllTables, tableNames };
