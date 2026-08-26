# FitSync server

Node/Express REST API backing the FitSync mobile app.

## Prerequisites

- Node.js 18 or later.
- MySQL 8. (MySQL 8's default `sql_mode` already includes
  `STRICT_TRANS_TABLES`, which the schema and its tests rely on — nothing
  extra to configure there on a stock install.)

## Database setup

Create two databases (one for normal use, one the test suite drops and
recreates freely) and a user with a real, private password — the block
below uses a placeholder:

```sql
CREATE DATABASE fitsync CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE fitsync_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'fitsync'@'localhost' IDENTIFIED BY '<choose-a-real-password>';
GRANT ALL PRIVILEGES ON fitsync.* TO 'fitsync'@'localhost';
GRANT ALL PRIVILEGES ON fitsync_test.* TO 'fitsync'@'localhost';
FLUSH PRIVILEGES;
```

Never commit the real password. `.env` is git-ignored for exactly this
reason, and a pre-commit hook refuses a staged `.env` or a populated
`.env.example`.

## Configuration

Copy the template and fill in your own values:

```
cp .env.example .env
```

Then edit `.env` and set at least `DB_PASSWORD` to the password you chose
above. `src/config/index.js` fails fast (refuses to boot) if any of
`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` are missing, or if
`PORT`/`DB_PORT` aren't positive integers.

## Install, migrate, run

```
npm install
npm run migrate   # applies src/db/migrations/*.sql, in order, to DB_NAME
npm test          # runs the suite against <DB_NAME>_test — see below
npm start         # starts the server on PORT (node server.js)
npm run dev       # same, restarting on file changes
```

`npm test` expects a live MySQL reachable with the credentials in `.env`,
and a `<DB_NAME>_test` database it can freely drop and recreate tables in
(the test helpers migrate that database from scratch as part of running).
To point the migration runner at the test database instead of the main
one for a one-off check, override `DB_NAME` on the command line:

```
DB_NAME=fitsync_test npm run migrate
```

See `MIGRATIONS.md` for the rules migration files follow and why.

### Re-migrating from scratch

While the project is pre-release, `MIGRATIONS.md` sanctions editing an
already-applied migration file in place. The runner has no checksum, so it
will not replay an edited file — it just reports "No pending migrations"
while your database keeps the old shape. **Pulling a branch that edited a
migration therefore means dropping every table and re-migrating.**

The `.env` user holds `ALL PRIVILEGES` on its own schema but only `USAGE`
globally, so drop the tables rather than the database. This is
non-interactive and asks for no password — it reuses the credentials in
`.env`, the same way `tests/helpers/test-db.js` does:

```bash
node -e "
const { load } = require('./src/config');
const mysql = require('mysql2/promise');
(async () => {
  const cfg = load().db;
  const c = await mysql.createConnection(cfg);
  const [rows] = await c.query(
    'SELECT table_name AS t FROM information_schema.tables WHERE table_schema = ?',
    [cfg.database],
  );
  await c.query('SET FOREIGN_KEY_CHECKS = 0');
  for (const r of rows) {
    await c.query('DROP TABLE IF EXISTS ' + mysql.escapeId(cfg.database) + '.' + mysql.escapeId(r.t));
  }
  await c.query('SET FOREIGN_KEY_CHECKS = 1');
  console.log('dropped ' + rows.length + ' tables');
  await c.end();
})();
"
npm run migrate
```

This destroys every row in `DB_NAME`. Re-run `npm run seed` afterwards to
restore the exercise catalogue. `npm test` migrates `<DB_NAME>_test` from
scratch on every run, so the test database needs nothing done to it.

## Exercise catalogue

The catalogue is seeded from [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset),
pinned to commit `7455efae`. Two phases:

```bash
npm run seed:fetch   # downloads 1,324 animations + thumbnails into storage/, writes the manifest
npm run seed         # upserts equipment, exercises and coaching_cues from the manifest
```

`seed:fetch` needs a network and takes several minutes; it is resumable and
skips assets already in `storage/`. `seed` needs neither network nor the
dataset — it reads only `src/db/seeds/exercises.json`, and runs in a single
transaction, so a failure leaves the database untouched. Both are idempotent.

Of the 1,324 exercises, 1,203 are seeded `live` and 121 `pending` — cardio
machines and niche equipment, held back for an admin review pass. Equipment
*availability* is a separate concern, handled by joining `user_equipment` at
query time.

**What a re-seed does and does not overwrite.** `status` is written on insert
only. That protects an admin who promoted a pending exercise from having the
decision undone by the next re-seed — but it cuts both ways: if you change the
promotion rule in `src/db/seeds/normalize.js` and re-run `npm run seed:fetch`,
the manifest will show the new `promote` values while `npm run seed` leaves
the `status` of every existing row exactly as it was, and still reports
success. Re-applying a changed rule to the existing catalogue needs an
explicit `UPDATE`. Coaching cues behave the opposite way — they are deleted
and re-inserted wholesale on every re-seed, so upstream edits do land and
hand-edited cue text does not survive.

If `npm run seed` fails with `ER_BAD_FIELD_ERROR: Unknown column 'source_id'`,
the database predates this branch's schema change. The migration runner will
not replay an edited file, so drop the tables and re-migrate (see
[Re-migrating from scratch](#re-migrating-from-scratch)), then seed again.

**Licensing:** see [`THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md).

## Response envelope

Every JSON response is one of exactly two shapes:

```jsonc
// success
{ "data": /* endpoint-specific payload */ }

// failure
{
  "error": {
    "code": "SOME_ERROR_CODE",
    "message": "Human-readable, client-safe description.",
    "details": []
  }
}
```

Handlers never emit anything outside those two shapes. Every response also
carries an `X-Request-Id` header (see `src/middleware/request-id.js`), and
every request is logged with that id, method, path, status and duration.

## Layout

- `src/config/` — loads and validates environment variables into one typed
  config object; refuses to start on missing or malformed values.
- `src/db/` — the MySQL connection pool (`pool.js`), the migration runner
  (`migrate.js`), and the migration files themselves (`migrations/`).
- `src/lib/` — small shared building blocks: the `AppError` type and the
  structured (pino) logger with credential redaction.
- `src/middleware/` — Express middleware: request-id assignment, the
  error-handling middleware, and the 404 handler.
- `src/routes/` — route registration; each resource gets its own router,
  mounted under `/api/v1`.
- `src/services/ml/` — the machine-learning service boundary (plan
  generation, injury risk), with a local `stub` driver and an `http`
  driver that calls out to a real ML service.
- `src/services/storage/` — the file storage boundary (`put`/`get`/
  `delete`/`exists`/`url`), with a `local` disk driver; the shape is meant
  to let an object-storage driver (S3, GCS) replace it later without
  touching callers.
- `src/app.js` — assembles the Express app: middleware chain, routes,
  error handling.
- `server.js` — the process entrypoint: builds config/logger/pool/services,
  starts listening, and handles graceful shutdown on `SIGTERM`/`SIGINT`.
