'use strict';
const mysql = require('mysql2/promise');

/// Every connection's session zone, so CURDATE(), NOW() and WEEKDAY() give
/// Manila's date on any host -- the day turns over at midnight in Manila, not
/// at whatever hour the host's own zone does. An offset rather than
/// 'Asia/Manila': a name needs MySQL's zone tables loaded, which many hosts
/// (and the dev database) lack, and the Philippines has kept no daylight
/// saving since 1978, so +08:00 is always exact.
///
/// This is the SQL session's zone only. mysql2's `timezone: 'Z'` below is a
/// separate setting, and every timestamp handed to the app is read through
/// UNIX_TIMESTAMP() (see sessions.js), which neither one affects.
const MANILA_OFFSET = '+08:00';

function createPool(dbConfig) {
  const pool = mysql.createPool({
    host: dbConfig.host,
    port: dbConfig.port,
    user: dbConfig.user,
    password: dbConfig.password,
    database: dbConfig.database,
    waitForConnections: true,
    connectionLimit: dbConfig.connectionLimit,
    queueLimit: 0,
    multipleStatements: false,
    charset: 'utf8mb4',
    timezone: 'Z',
  });
  // A connection runs its commands in order, so this SET lands before any
  // query the pool later hands the connection. If it fails, the connection
  // is destroyed rather than left to date rows by the host's zone.
  pool.pool.on('connection', (conn) => {
    conn.query(`SET time_zone = '${MANILA_OFFSET}'`, (err) => {
      if (err) conn.destroy();
    });
  });
  return pool;
}

module.exports = { createPool, MANILA_OFFSET };
