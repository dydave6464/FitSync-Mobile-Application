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
