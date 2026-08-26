'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { dropAllTables, testDbConfig } = require('./helpers/test-db');

function fakePool(rows) {
  const connQueries = [];
  const pool = {
    async query() {
      return [rows];
    },
    async getConnection() {
      return {
        async query(sql) {
          connQueries.push(sql);
          return [[]];
        },
        release() {},
      };
    },
  };
  return { pool, connQueries };
}

test('dropAllTables qualifies DROP TABLE with the escaped test database name', async () => {
  const { pool, connQueries } = fakePool([{ t: 'users' }, { t: 'orders' }]);
  await dropAllTables(pool);

  const cfg = testDbConfig();
  const dropStatements = connQueries.filter((q) => q.startsWith('DROP TABLE'));

  assert.equal(dropStatements.length, 2);
  assert.equal(dropStatements[0], `DROP TABLE IF EXISTS \`${cfg.database}\`.\`users\``);
  assert.equal(dropStatements[1], `DROP TABLE IF EXISTS \`${cfg.database}\`.\`orders\``);
});

test('dropAllTables escapes a hostile table name rather than interpolating it raw', async () => {
  const { pool, connQueries } = fakePool([{ t: 'weird`table' }]);
  await dropAllTables(pool);

  const cfg = testDbConfig();
  const dropStatements = connQueries.filter((q) => q.startsWith('DROP TABLE'));
  assert.equal(dropStatements[0], `DROP TABLE IF EXISTS \`${cfg.database}\`.\`weird\`\`table\``);
});
