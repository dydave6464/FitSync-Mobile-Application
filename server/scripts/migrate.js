'use strict';
const { load } = require('../src/config');
const { migrate } = require('../src/db/migrate');

migrate(load().db)
  .then((applied) => {
    console.log(applied.length ? `Applied: ${applied.join(', ')}` : 'No pending migrations.');
    process.exit(0);
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
