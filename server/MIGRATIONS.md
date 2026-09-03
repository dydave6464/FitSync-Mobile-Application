# Migration policy

This documents the convention the migration runner (`src/db/migrate.js`)
relies on but does not enforce. Read it before adding or editing a file in
`src/db/migrations/`.

## The rule

A migration file may contain **`CREATE TABLE IF NOT EXISTS` statements and
nothing else.**

Specifically, a migration file must **not** contain:

- Seed `INSERT` statements.
- A standalone `CREATE INDEX`. Indexes belong inside the `CREATE TABLE` body
  (as `INDEX`/`UNIQUE KEY` clauses), not as separate statements.
- `ALTER TABLE`.

## Why this is the rule, not just a preference

MySQL implicitly commits the current transaction before and after most DDL
statements. That means a multi-statement migration file gets **no
rollback** if something partway through fails — whatever ran before the
failure has already been committed, whether or not you started an explicit
transaction around it.

The runner records a migration as applied only after the whole file has
executed successfully (see `applied.push(file)` / the
`INSERT INTO schema_migrations` in `src/db/migrate.js`, which only happens
after the file's `connection.query(sql)` call returns). So if a file fails
partway through, the next run replays the **entire file from the top** —
none of it was recorded as done.

`CREATE TABLE IF NOT EXISTS` is the only statement shape that survives that
replay safely: whatever tables the failed run managed to create before
dying are simply skipped (`IF NOT EXISTS`) on the retry, and the statements
that didn't run yet do now. A seed `INSERT`, a bare `CREATE INDEX`, or an
`ALTER TABLE` has no such idempotent retry — run it twice and you get
duplicate rows, a "duplicate key name" error, or a "duplicate column"
error, respectively.

## Filenames and ordering

Filenames are zero-padded three-digit sequence numbers followed by a short
name, e.g. `001_account_and_profile.sql`, `002_training.sql`. The runner
sorts filenames lexicographically and applies them in that order
(`entries.filter(...).sort()` in `src/db/migrate.js`), so the zero-padding
has to be kept up — the convention holds through `999_*.sql`. Do not reuse
or renumber an already-applied filename.

## Pre-release: editing migrations in place

**Right now**, with no production data and both `fitsync` and `fitsync_test`
freely dropped and re-migrated, the practical policy is: **edit the
existing migration file in place** rather than adding a new `ALTER`-based
migration, then drop all tables and re-run `npm run migrate` (see
`README.md` for the exact commands) so the change actually lands. This
keeps the schema's history in one file per logical area instead of a long
tail of patches, which is only affordable because there is nothing to lose
by starting over.

**This stops being safe the moment real data exists.** Once there are rows
a re-migrate-from-scratch would destroy, in-place edits to already-applied
migration files must stop, and new schema changes need actual `ALTER`
migrations (or an equivalent forward-only mechanism) with a real rollback
and data-migration story. That transition is an **open item for a later
sub-project** — it has not been designed yet.

## Exceptions: `007_auth_identities.sql`, `008_equipment_curation.sql`

Both files break the rule above on purpose, for the same reason: each needs
to change tables that migrations `001`–`006` already defined and that may
already be applied on someone's database. The runner has no checksum (see the
gap recorded below): it decides whether to apply a file solely by filename,
so editing e.g. `001_account_and_profile.sql` in place to add these columns
would not be replayed on a database where `001` was already recorded as
applied — the edit would be silently invisible there, exactly the failure
mode the pre-release policy above depends on nobody hitting. A new,
forward-only file sidesteps that. The tradeoff is the one below: unlike a
`CREATE TABLE IF NOT EXISTS`-only file, neither of these is safe to replay
after a partial failure.

**`007_auth_identities.sql`** — alongside its
`CREATE TABLE IF NOT EXISTS user_identities`, it contains six `ALTER TABLE`
statements against `users`, `injuries`, `user_injuries` and `exercises`
(making `password_hash` nullable, changing the `main_goal` enum, adding
`notifications_enabled`, `onboarding_completed_at`, `is_lateral`,
`region_group`, `side` and `body_part`).

**`008_equipment_curation.sql`** — alongside four `ALTER TABLE equipment ADD
COLUMN` statements (`display_name`, `display_order`, `is_user_selectable`,
`parent_equipment_id`, plus the `fk_equipment_parent` foreign key), it
contains a standalone `CREATE INDEX idx_equipment_selectable ON equipment
(is_user_selectable, display_order)` — the other forbidden shape, alongside
`ALTER TABLE` itself.

**Consequence: neither is replay-safe.** Unlike every other migration file,
if 007 or 008 fails partway through, `IF NOT EXISTS` does not protect the
`ALTER TABLE` (or, for 008, the trailing `CREATE INDEX`) statements — a
second run will hit `ER_DUP_FIELDNAME` (or, for the index, the equivalent
"duplicate key name" error) on whichever statement had already committed.
Because `ALTER TABLE` and `CREATE INDEX` both implicitly commit, a partial
failure is not rolled back by the runner failing to record the version.

**If 007 or 008 fails partway through**, recovery is manual:

1. Inspect the actual table shape to see exactly which statements already
   committed: for 007, `DESCRIBE users;`, `DESCRIBE injuries;`, `DESCRIBE
   user_injuries;`, `DESCRIBE exercises;`, and confirm whether
   `user_identities` exists; for 008, `DESCRIBE equipment;` and `SHOW INDEX
   FROM equipment;`.
2. Comment out (or delete) the statements in a local copy of the migration
   file that already applied, leaving only the ones that did not.
3. Re-run `npm run migrate`. Since the runner never recorded the file as
   applied (it did not finish), it will attempt it again; with the
   already-applied statements removed, the remainder can complete.
4. Restore the migration file to its original committed contents afterwards
   — the trimmed copy was a local recovery aid only, not a replacement
   migration.

On a pre-release database (see the section above), it is almost always
simpler to drop all tables and re-migrate from scratch instead.

## Known gap: no two-phase record or checksum

The runner records a migration as applied (in `schema_migrations`) only
after the file succeeds — there is no "in progress" row written before the
attempt. If a file fails partway through, cleanup today is **manual**: you
have to make sure the file replays safely (see above), or hand-clean the
partial state before retrying. There is also no checksum on applied
migrations, so an already-applied file that is edited afterwards will not
be re-applied and will not be flagged as changed. Both are known gaps, not
yet built.

## The ML service's read-only grant

Migration 009 adds two tables the Python plan generator reads. It gets a
read-only account scoped to the seed-driven reference tables and nothing else
— it never reads `users`, `workout_plans`, or any other user row. Apply this
by hand after running the migration:

```sql
CREATE USER IF NOT EXISTS 'fitsync_ml'@'%' IDENTIFIED BY '<password>';
GRANT SELECT ON fitsync.exercises TO 'fitsync_ml'@'%';
GRANT SELECT ON fitsync.equipment TO 'fitsync_ml'@'%';
GRANT SELECT ON fitsync.exercise_equipment_requirements TO 'fitsync_ml'@'%';
GRANT SELECT ON fitsync.exercise_contraindications TO 'fitsync_ml'@'%';
GRANT SELECT ON fitsync.exercise_categories TO 'fitsync_ml'@'%';
FLUSH PRIVILEGES;
```

Migration 010 adds a fifth reference table. The service still reads no user
row.

The grant is deliberately not `GRANT SELECT ON fitsync.*`. If the service ever
needs another table, adding a line here should be a decision someone makes,
not something that already happened.

## The ML service's test database

The Python suite must not share `fitsync_test` with the Node suite. The Node
helper `server/tests/helpers/test-db.js` drops every table in it, so `npm test`
removed the tables the Python integration tests need -- and those tests
answered a missing table with a *skip*, which exits 0. Twenty tests silently
stopped running while both suites reported success.

Give the ML suite its own database. Apply this by hand, as an admin:

```sql
CREATE DATABASE IF NOT EXISTS fitsync_ml_test
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON fitsync_ml_test.* TO 'fitsync'@'localhost';
FLUSH PRIVILEGES;
```

Then migrate it like any other: `DB_NAME=fitsync_ml_test npm run migrate`. It
is a throwaway schema on the same terms as `fitsync_test` -- drop and
re-migrate it freely.

Unlike `fitsync_ml`, this grant is deliberately **not** read-only: the Python
fixtures create and delete their own catalogue rows. That is also why it must
never point at `fitsync`; `ml/tests/dbgate.py` refuses any test database whose
name does not end in `_test`.
