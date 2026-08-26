'use strict';
const express = require('express');

module.exports = function buildHealthRouter({ pool }) {
  const router = express.Router();

  router.get('/', async (req, res) => {
    let database = 'down';
    if (pool) {
      try {
        await pool.query('SELECT 1');
        database = 'up';
      } catch {
        database = 'down';
      }
    }

    const status = database === 'up' ? 'ok' : 'degraded';
    res.status(status === 'ok' ? 200 : 503).json({
      data: { status, database, uptime: Math.floor(process.uptime()) },
    });
  });

  return router;
};
