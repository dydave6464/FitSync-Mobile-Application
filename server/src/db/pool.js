'use strict';
const mysql = require('mysql2/promise');

function createPool(dbConfig) {
  return mysql.createPool({
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
}

module.exports = { createPool };
