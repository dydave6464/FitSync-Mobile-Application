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

## Exception: `007_auth_identities.sql`

`007_auth_identities.sql` breaks the rule above on purpose: alongside its
`CREATE TABLE IF NOT EXISTS user_identities`, it contains six `ALTER TABLE`
statements against `users`, `injuries`, `user_injuries` and `exercises`
(making `password_hash` nullable, changing the `main_goal` enum, adding
`notifications_enabled`, `onboarding_completed_at`, `is_lateral`,
`region_group`, `side` and `body_part`).

This was not an oversight. The columns and table it changes were defined by
migrations `001`–`006`, already applied on any database anyone had already
migrated. The runner has no checksum (see the gap recorded below): it decides
whether to apply a file solely by filename, so editing
`001_account_and_profile.sql` in place to add these columns would not be
replayed on a database where `001` was already recorded as applied — the
edit would be silently invisible there, exactly the failure mode the
pre-release policy above depends on nobody hitting. A new, forward-only file
sidesteps that. The tradeoff is the one below: unlike a
`CREATE TABLE IF NOT EXISTS`-only file, this one is not safe to replay after
a partial failure.

**Consequence: 007 is not replay-safe.** Unlike every other migration file,
if 007 fails partway through, `IF NOT EXISTS` does not protect the `ALTER
TABLE` statements — a second run will hit `ER_DUP_FIELDNAME` (or the
equivalent "duplicate column/key" error) on whichever statement had already
committed. Because `ALTER TABLE` implicitly commits, a partial failure is not
rolled back by the runner failing to record the version.

**If 007 fails partway through**, recovery is manual:

1. Inspect the actual table shapes (`DESCRIBE users;`, `DESCRIBE injuries;`,
   `DESCRIBE user_injuries;`, `DESCRIBE exercises;`, and confirm whether
   `user_identities` exists) to see exactly which of the six `ALTER`
   statements already committed.
2. Comment out (or delete) the statements in a local copy of
   `007_auth_identities.sql` that already applied, leaving only the ones that
   did not.
3. Re-run `npm run migrate`. Since the runner never recorded `007` as applied
   (the file did not finish), it will attempt it again; with the
   already-applied statements removed, the remainder can complete.
4. Restore `007_auth_identities.sql` to its original committed contents
   afterwards — the trimmed copy was a local recovery aid only, not a
   replacement migration.

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
