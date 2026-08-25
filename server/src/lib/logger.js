'use strict';
const pino = require('pino');

function createLogger({ level = 'info', env = 'development' } = {}) {
  const options = {
    level,
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'password',
        '*.password',
        '*.*.password',
        'req.body.password',
        'password_hash',
        '*.password_hash',
        '*.*.password_hash',
        'req.body.password_hash',
        'token',
        '*.token',
        '*.*.token',
        'req.body.token',
      ],
      censor: '[REDACTED]',
    },
  };

  if (env === 'development') {
    options.transport = { target: 'pino-pretty', options: { colorize: true } };
  }

  return pino(options);
}

module.exports = { createLogger };
