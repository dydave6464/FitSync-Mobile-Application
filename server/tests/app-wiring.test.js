'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const { createApp } = require('../src/app');
const { createMlService } = require('../src/services/ml');
const { createStorage } = require('../src/services/storage');
const { silentLogger } = require('./helpers/test-app');

test('services are reachable from a request handler', async () => {
  const probe = express.Router();
  probe.get('/probe', (req, res) => {
    res.json({
      data: {
        hasMl: typeof req.services.ml.generatePlan === 'function',
        hasStorage: typeof req.services.storage.put === 'function',
      },
    });
  });

  const app = createApp({
    config: { env: 'test' },
    logger: silentLogger(),
    pool: null,
    ml: createMlService({ mode: 'stub' }),
    storage: createStorage({ mode: 'local', localDir: 'storage' }),
    extraRouter: probe,
  });

  const res = await request(app).get('/api/v1/probe');
  assert.equal(res.status, 200);
  assert.equal(res.body.data.hasMl, true);
  assert.equal(res.body.data.hasStorage, true);
});

test('the app builds with no services supplied', async () => {
  const app = createApp({ config: { env: 'test' }, logger: silentLogger(), pool: null });
  const res = await request(app).get('/api/v1/health');
  assert.equal(res.status, 503);
});

test('req.services never exposes database credentials', async () => {
  const probe = express.Router();
  probe.get('/probe', (req, res) => {
    res.json({ data: { services: JSON.parse(JSON.stringify(req.services)) } });
  });
  const app = createApp({
    config: { env: 'test', db: { password: 'SUPER_SECRET_PW', user: 'dbuser' } },
    logger: silentLogger(),
    pool: null,
    extraRouter: probe,
  });
  const res = await request(app).get('/api/v1/probe');
  const body = JSON.stringify(res.body);
  assert.doesNotMatch(body, /SUPER_SECRET_PW/);
  assert.doesNotMatch(body, /dbuser/);
  assert.equal(res.body.data.services.config.db, undefined);
});
