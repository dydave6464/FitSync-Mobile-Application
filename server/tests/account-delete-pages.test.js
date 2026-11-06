'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { hashToken, issueToken } = require('../src/lib/auth-tokens');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { createMailService } = require('../src/services/mail');
const { DAILY_LINK_LIMIT } = require('../src/db/account');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

const BASE = 'https://fitsync.example';
const PAGE = '/api/v1/account/delete-request';
const CONFIRM = `${PAGE}/confirm`;
const SENT = "If an account uses this email, we&#39;ve sent a link to delete it.";
const EXPIRED = 'This link has expired. Ask for a new one.';
const DELETED = 'Your account and its data were deleted.';

test('delete account from the web', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const mail = createMailService({ mode: 'stub' }, { info() {} });
  const app = buildTestApp({ pool, mail, publicBaseUrl: BASE });

  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const reset = async () => {
    await pool.query('DELETE FROM users');
    mail.sent.length = 0;
  };

  const newUser = async (email = 'ana@example.com') => {
    const [r] = await pool.query(
      'INSERT INTO users (email, password_hash, full_name, email_verified) VALUES (?, ?, ?, 1)',
      [email, 'x', 'Ana'],
    );
    await pool.query(
      'INSERT INTO body_weight_logs (user_id, weight_kg, log_date) VALUES (?, 70, CURDATE())',
      [r.insertId],
    );
    return r.insertId;
  };
  const userExists = async (userId) => {
    const [[row]] = await pool.query('SELECT COUNT(*) AS n FROM users WHERE user_id = ?', [userId]);
    return Number(row.n) === 1;
  };

  const ask = (email) => request(app).post(PAGE).type('form').send({ email });
  const linkIn = (message) => message.text.match(/https:\/\/\S+/)[0];
  const tokenIn = (link) => new URL(link).searchParams.get('token');
  const open = (token) => request(app).get(`${CONFIRM}?token=${encodeURIComponent(token)}`);
  const confirm = (token) => request(app).post(CONFIRM).type('form').send({ token });

  /// A delete link for [userId], as the request page would mail it.
  const linkFor = async (userId) => issueToken(pool, { userId, purpose: 'delete_account' });

  await t.test('the request page explains deletion and asks for the email', async () => {
    const res = await request(app).get(PAGE).expect(200);
    assert.match(res.headers['content-type'], /text\/html/);
    assert.match(res.text, /can&#39;t be undone/);
    assert.match(res.text, new RegExp(`<form method="post" action="${PAGE}">`));
    assert.match(res.text, /<label for="email">/);
    assert.match(res.text, /<input id="email" name="email" type="email"/);
    // The page is reachable without an app sign-in, and its form posts to a
    // plain-http host too (the phone hotspot): no upgrade-insecure-requests.
    assert.doesNotMatch(res.headers['content-security-policy'], /upgrade-insecure-requests/);
  });

  await t.test('a known and an unknown email get the same page; only the known one is mailed', async () => {
    await reset();
    const userId = await newUser('ana@example.com');

    const known = await ask('Ana@Example.com ');
    const unknown = await ask('nobody@example.com');

    assert.equal(known.status, 200);
    assert.equal(unknown.status, known.status);
    assert.equal(unknown.text, known.text, 'byte-identical: the page never says which');
    assert.ok(known.text.includes(SENT));

    assert.equal(mail.sent.length, 1);
    const [message] = mail.sent;
    assert.equal(message.to, 'ana@example.com');
    assert.match(message.subject, /delete your FitSync account/i);
    const link = linkIn(message);
    assert.ok(link.startsWith(`${BASE}${CONFIRM}?token=`), link);

    const [rows] = await pool.query(
      "SELECT token_hash, user_id FROM auth_tokens WHERE purpose = 'delete_account'",
    );
    assert.equal(rows.length, 1);
    assert.equal(rows[0].user_id, userId);
    assert.equal(rows[0].token_hash, hashToken(tokenIn(link)), 'only the hash is stored');
  });

  await t.test('a blank or malformed email gets the same page and sends nothing', async () => {
    await reset();
    await newUser();
    const known = await ask('ana@example.com');
    mail.sent.length = 0;

    for (const body of [{}, { email: '' }, { email: 'not an email' }]) {
      const res = await request(app).post(PAGE).type('form').send(body);
      assert.equal(res.status, 200);
      assert.equal(res.text, known.text);
    }
    assert.equal(mail.sent.length, 0);
  });

  await t.test('the link in the email ignores the Host the request came with', async () => {
    await reset();
    await newUser();
    await ask('ana@example.com').set('Host', 'evil.example').expect(200);
    assert.ok(linkIn(mail.sent[0]).startsWith(`${BASE}/`), 'a forged Host cannot steer the link');
  });

  await t.test('asking again within a minute sends no second email', async () => {
    await reset();
    await newUser();
    const first = await ask('ana@example.com');
    const second = await ask('ana@example.com');
    assert.equal(second.text, first.text);
    assert.equal(mail.sent.length, 1);
  });

  await t.test('no account gets more than the daily limit of links', async () => {
    await reset();
    const userId = await newUser();
    // Earlier today's links, each past the one-minute cooldown.
    for (let i = 0; i < DAILY_LINK_LIMIT; i += 1) {
      await issueToken(pool, { userId, purpose: 'delete_account' });
    }
    await pool.query(
      `UPDATE auth_tokens SET created_at = DATE_SUB(NOW(), INTERVAL 2 HOUR)
        WHERE user_id = ? AND purpose = 'delete_account'`, [userId],
    );

    await ask('ana@example.com').expect(200);
    assert.equal(mail.sent.length, 0);

    // A day later the oldest no longer count.
    await pool.query(
      `UPDATE auth_tokens SET created_at = DATE_SUB(NOW(), INTERVAL 25 HOUR)
        WHERE user_id = ? AND purpose = 'delete_account'`, [userId],
    );
    await ask('ana@example.com').expect(200);
    assert.equal(mail.sent.length, 1);
  });

  await t.test('a live link opens the confirm page, which does not spend it', async () => {
    await reset();
    const userId = await newUser();
    const token = await linkFor(userId);

    const res = await open(token).expect(200);
    assert.match(res.text, /can&#39;t be undone/);
    assert.match(res.text, new RegExp(`<form method="post" action="${CONFIRM}">`));
    assert.ok(res.text.includes(`<input type="hidden" name="token" value="${token}">`));
    assert.match(res.text, /<button type="submit" class="danger">Delete my account<\/button>/);
    assert.equal(res.headers['cache-control'], 'no-store');
    assert.equal(res.headers['x-robots-tag'], 'noindex, nofollow');

    assert.ok(await userExists(userId));
    await open(token).expect(200);
  });

  await t.test('an expired, used or unknown link gets the same expired page', async () => {
    await reset();
    const userId = await newUser();
    const expired = await linkFor(userId);
    await pool.query(
      'UPDATE auth_tokens SET expires_at = DATE_SUB(NOW(), INTERVAL 1 SECOND) WHERE token_hash = ?',
      [hashToken(expired)],
    );
    const used = await linkFor(userId);
    await pool.query('UPDATE auth_tokens SET consumed_at = NOW() WHERE token_hash = ?', [hashToken(used)]);
    // Purpose-bound: a token issued for something else is no delete link.
    const other = await issueToken(pool, { userId, purpose: 'reset_password' });

    const pages = [];
    for (const token of [expired, used, other, 'nonsense']) {
      const res = await open(token);
      assert.equal(res.status, 404);
      pages.push(res.text);
    }
    pages.push((await request(app).get(CONFIRM)).text);
    for (const page of pages) assert.equal(page, pages[0]);
    assert.ok(pages[0].includes(EXPIRED));
    assert.ok(pages[0].includes(`<a href="${PAGE}">`), 'a link back to ask for a new one');
    assert.ok(await userExists(userId));
  });

  await t.test('confirming deletes the account and spends the link', async () => {
    await reset();
    const userId = await newUser();
    const keptId = await newUser('kept@example.com');
    const token = await linkFor(userId);

    const res = await confirm(token).expect(200);
    assert.ok(res.text.includes(DELETED));
    assert.equal(res.headers['cache-control'], 'no-store');

    assert.equal(await userExists(userId), false);
    const [[left]] = await pool.query(
      'SELECT COUNT(*) AS n FROM body_weight_logs WHERE user_id = ?', [userId],
    );
    assert.equal(Number(left.n), 0, 'its data went with it');
    const [[tokens]] = await pool.query(
      'SELECT COUNT(*) AS n FROM auth_tokens WHERE token_hash = ?', [hashToken(token)],
    );
    assert.equal(Number(tokens.n), 0, 'the link is gone with the account');
    assert.ok(await userExists(keptId), 'nobody else was deleted');

    const again = await confirm(token);
    assert.equal(again.status, 404);
    assert.ok(again.text.includes(EXPIRED));
  });

  await t.test('confirming with a dead link gets the expired page and deletes nothing', async () => {
    await reset();
    const userId = await newUser();
    const expired = await linkFor(userId);
    await pool.query(
      'UPDATE auth_tokens SET expires_at = DATE_SUB(NOW(), INTERVAL 1 SECOND) WHERE token_hash = ?',
      [hashToken(expired)],
    );

    for (const body of [{ token: expired }, { token: 'nonsense' }, {}]) {
      const res = await request(app).post(CONFIRM).type('form').send(body);
      assert.equal(res.status, 404);
      assert.ok(res.text.includes(EXPIRED));
    }
    assert.ok(await userExists(userId));
  });

  await t.test('the token is escaped where the page repeats it', async () => {
    await reset();
    const userId = await newUser();
    // Never a token issueToken would make, but the page must not trust that.
    const crafted = '"><script>alert(1)</script>';
    await pool.query(
      `INSERT INTO auth_tokens (token_hash, user_id, purpose, expires_at)
       VALUES (?, ?, 'delete_account', DATE_ADD(NOW(), INTERVAL 1 HOUR))`,
      [hashToken(crafted), userId],
    );

    const res = await open(crafted).expect(200);
    assert.ok(!res.text.includes('<script>alert(1)</script>'));
    assert.ok(res.text.includes(
      'value="&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"',
    ));
  });
});
