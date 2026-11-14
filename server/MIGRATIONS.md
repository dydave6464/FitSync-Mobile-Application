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

## Exceptions: `007`, `008`, `011`, `012`, `013`, `014`, `017`, `028`, `032`, `033`, `034`, `035`, `036`, `037`, `038`, `042`, `044`, `045`, `046`, `047`, `048`, `049`, `050`, `051`, `053` and `054`

`007_auth_identities.sql`, `008_equipment_curation.sql`,
`011_email_verification.sql`, `012_weight_unit.sql`, `013_plan_days.sql`,
`014_cardio_core_split.sql`, `017_plan_source.sql`,
`028_new_to_training_level.sql`, `032_nutrition_tracking.sql`,
`033_food_fiber.sql`, `034_meal_log_fiber.sql`, `035_food_sugar_sodium.sql`,
`036_meal_log_sugar_sodium.sql`, `037_injury_risk_drivers.sql` and
`038_food_types.sql`, `042_account_deletion.sql`,
`044_user_suspension.sql`, `045_food_hiding.sql`, `046_ad_details.sql`,
`047_revenue_payments.sql`, `048_meal_suggestions.sql`, `049_usual_rice_cups.sql`,
`050_food_contains.sql`, `051_user_avoid_foods.sql`, `053_food_photo.sql` and
`054_plan_replaced.sql`.

All twenty-six files break the rule above on purpose. Twenty-five of them do so for
the same reason: each needs to change tables that migrations `001`–`006`
already defined and that may already be applied on someone's database.
The runner has no checksum
(see the gap recorded below): it decides whether to apply a file solely by
filename, so editing e.g. `001_account_and_profile.sql` in place to add
these columns would not be replayed on a database where `001` was already
recorded as applied — the edit would be silently invisible there, exactly
the failure mode the pre-release policy above depends on nobody hitting. A
new, forward-only file sidesteps that. `047` is the odd one: it creates a new
table, then copies rows already in `pro_payments` into it (see its entry
below). The tradeoff is the one below: unlike
a `CREATE TABLE IF NOT EXISTS`-only file, eight of the twenty-six are not safe to
replay after a partial failure. `014`, `028`, `032`, `033`, `034`, `035`,
`036`, `037`, `038`, `042`, `044`, `045`, `046`, `047`, `049`, `051`, `053` and `054` are the exceptions to the exception, and they
replay cleanly for different reasons: `014` and `028` restate a column
definition rather than adding to one, while `032`, `033`, `034`, `035`, `036`,
`037` and `038` rely on MySQL 8's atomic DDL — `032` also on statement
ordering, `033`, `034`, `035`, `036`, `037` and `038` on the DDL alone, since
each of those six files is nothing but the one `ALTER`. `042` combines the
two: it restates the `purpose` column like `014`, then ends on one atomic
`ADD COLUMN` like `032`; `044`, `045`, `049`, `051` and `053` are each one atomic `ADD COLUMN` like
`033`, and `046` and `054` each one atomic `ALTER`, for the same reason (see their entries
below); `047` is a `CREATE TABLE IF NOT EXISTS` followed by an `INSERT
IGNORE` keyed on the primary key. Which of the twenty-six you
are holding is the thing to know before retrying one.

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

**`011_email_verification.sql`** — alongside its
`CREATE TABLE IF NOT EXISTS auth_tokens`, it contains one
`ALTER TABLE users ADD COLUMN email_verified` statement. Verification is a
hard gate (an unverified account is issued no token and cannot sign in), so
this column decides access, not merely data quality — see the design,
section 2.

**`012_weight_unit.sql`** — one
`ALTER TABLE users ADD COLUMN weight_unit` statement. Every stored figure
stays metric; the column decides display and input parsing only, which is
why it lives with the account rather than the device.

**`013_plan_days.sql`** — two `ALTER TABLE ... ADD COLUMN` statements, one
against `plan_exercises` (`day_no`) and one against `workout_sessions`
(`plan_day_no`), so a plan becomes a rotation of days instead of one flat
list. This is the file whose own comment points here for recovery, which is
what makes its absence from this section worth correcting.

**`014_cardio_core_split.sql`** — one
`ALTER TABLE workout_plans MODIFY COLUMN split_style` statement, appending
`cardio_core` to the enum `002` defined. Appended at the END of the value
list: MySQL stores an enum as an index into that list, so inserting in the
middle would renumber the values after it and silently change what every
existing row means.

**`017_plan_source.sql`** — one
`ALTER TABLE workout_plans ADD COLUMN source` statement, recording whether a
plan was produced by the generator or built from workouts the user actually
completed (`POST /plans/from-session`). An `ADD COLUMN`, like 007, 008, 011,
012 and 013 — not a `MODIFY COLUMN` like 014 and 028 — so it is not
replay-safe.

**`028_new_to_training_level.sql`** — one
`ALTER TABLE users MODIFY COLUMN fitness_level` statement, appending `new` to
the enum `001` defined. Appended at the END for the same reason as 014. Like
014 it restates the whole column definition, so it replays cleanly.

**`032_nutrition_tracking.sql`** — a `CREATE TABLE IF NOT EXISTS food_sources`
followed by ONE `ALTER TABLE meal_logs` (adds `serving_desc`, widens
`protein_g`/`carbs_g`/`fat_g` to DECIMAL(7,2)). The ALTER is last and is a
single atomic statement, so a failure anywhere replays cleanly: before it,
nothing non-idempotent has run; inside it, nothing was applied.

**Consequence: eight of the twenty-six are not replay-safe.** Unlike every other
migration file, if 007, 008, 011, 012, 013, 017, 048 or 050 fails partway through,
`IF NOT EXISTS` does not protect the `ALTER TABLE` (or, for 008, the
trailing `CREATE INDEX`) statements — a second run will hit
`ER_DUP_FIELDNAME` (or, for 008's index, the equivalent "duplicate key name"
error) on whichever statement had already committed. Because `ALTER TABLE`
and `CREATE INDEX` both implicitly commit, a partial failure is not rolled
back by the runner failing to record the version.

**014, 028, 032, 033, 034, 035, 036, 037, 038, 042, 044, 045, 046, 047, 049, 051, 053 and 054 are the ones that can simply be re-run.** 014 and 028
both use `MODIFY COLUMN`, which restates the column's whole definition rather
than adding to it, so re-running the file is what is safe: it sets the same
values both times — `014` on the split_style enum, `028` on fitness_level —
with no `ER_DUP_FIELDNAME` to hit. That is a property of the statement, not
of the runner — the runner still has no checksum and still records a file
only once it fully succeeds — so it applies to these two files and not to the
other six.

032 is different, and the caveat matters: its `ALTER TABLE` does `ADD
COLUMN`, which would hit `ER_DUP_FIELDNAME` if it ever ran twice. It replays
cleanly only because of statement ordering plus MySQL 8's atomic DDL — the
`CREATE TABLE IF NOT EXISTS` before it is idempotent, and the one `ALTER` is
last and either applies whole or not at all, so a failed run never leaves
part of it behind to collide with. Split that `ALTER` in two, add a statement
after it, or run it on a server without atomic DDL, and 032 is no more
replay-safe than the six.

**`033_food_fiber.sql`** — one `ALTER TABLE foods ADD COLUMN fiber_g`, a
single atomic statement; a failure inside it applied nothing, but a run that
applied it and was not recorded would hit `ER_DUP_FIELDNAME` on re-run.

**`034_meal_log_fiber.sql`** — one `ALTER TABLE meal_logs ADD COLUMN
fiber_g`, a single atomic statement; a failure inside it applied nothing, but
a run that applied it and was not recorded would hit `ER_DUP_FIELDNAME` on
re-run.

**`035_food_sugar_sodium.sql`** — one `ALTER TABLE foods ADD COLUMN sugar_g
…, ADD COLUMN sodium_mg …`, a single atomic statement; a failure inside it
applied nothing, but a run that applied it and was not recorded would hit
`ER_DUP_FIELDNAME` on re-run.

**`036_meal_log_sugar_sodium.sql`** — one `ALTER TABLE meal_logs ADD COLUMN
sugar_g …, ADD COLUMN sodium_mg …`, a single atomic statement; a failure
inside it applied nothing, but a run that applied it and was not recorded
would hit `ER_DUP_FIELDNAME` on re-run.

**`037_injury_risk_drivers.sql`** — one `ALTER TABLE injury_risk_estimates
ADD COLUMN source …, ADD COLUMN model_version …, ADD COLUMN load_pct …, ADD
COLUMN drivers …`, a single atomic statement; a failure inside it applied
nothing, but a run that applied it and was not recorded would hit
`ER_DUP_FIELDNAME` on re-run. All four columns are nullable, so estimates
stored before it read back with no source, load or drivers.

**`038_food_types.sql`** — one `ALTER TABLE foods ADD COLUMN food_type …,
ADD COLUMN list_order …`, a single atomic statement; a failure inside it
applied nothing, but a run that applied it and was not recorded would hit
`ER_DUP_FIELDNAME` on re-run. Both columns are nullable: FatSecret copies and
foods outside the seed list keep no type or place, and `npm run seed:foods`
fills them in for FitSync's own foods.

**`042_account_deletion.sql`** — an `ALTER TABLE auth_tokens MODIFY COLUMN
purpose` appending `delete_account` to the enum `011` defined (at the END, as
014), followed by ONE `ALTER TABLE users ADD COLUMN token_version`, the token
generation a password change or reset moves on to sign out older tokens. It
replays cleanly for the same reasons as 014 and 032 combined: the `MODIFY`
restates the whole column, and the `ADD COLUMN` is last and atomic, so a
failed run never leaves part of it behind. Add a statement after it and that
stops being true.

**`044_user_suspension.sql`** — one `ALTER TABLE users ADD COLUMN
suspended_at TIMESTAMP NULL DEFAULT NULL`, the moment an admin suspended the
account (`NULL` = active). While it is set, sign-in, Google sign-in and every
authenticated request answer `ACCOUNT_SUSPENDED`. The file is nothing but
that one atomic `ADD COLUMN` (042's reasoning for its last statement), so a
failure inside it applied nothing and a failed run replays cleanly; a run that
applied it and was not recorded would hit `ER_DUP_FIELDNAME` on re-run. Add a
statement after it and that stops being true.

**`045_food_hiding.sql`** — one `ALTER TABLE foods ADD COLUMN hidden_at
TIMESTAMP NULL DEFAULT NULL`, the moment an admin hid one of FitSync's own
foods (`NULL` = shown). A hidden food leaves food search, Recents and Snap a
meal's menu; logging it by id, and meals already logged, are unaffected. Like
`044`, the file is nothing but that one atomic `ADD COLUMN`, so a failure
inside it applied nothing and a failed run replays cleanly; a run that applied
it and was not recorded would hit `ER_DUP_FIELDNAME` on re-run. Add a
statement after it and that stops being true.

**`046_ad_details.sql`** — one `ALTER TABLE advertisements` adding seven
columns: `link_url`, `advertiser`, `amount_php`, `starts_on`, `ends_on`,
`views` and `taps` (FitSync's own ads: who paid, how much, when the ad runs,
and how often free trainees saw and tapped it). The seven `ADD COLUMN`
clauses are one statement, so MySQL 8 applies all of them or none: a failure
inside it applied nothing and a failed run replays cleanly; a run that
applied it and was not recorded would hit `ER_DUP_FIELDNAME` on re-run. Add a
statement after it, or split it into one `ALTER` per column, and that stops
being true.

**`047_revenue_payments.sql`** — a `CREATE TABLE IF NOT EXISTS
revenue_payments` (an anonymous copy of each paid Pro payment: plan, amount,
method and the Manila day it was paid; no user, no PayMongo reference, and no
foreign key, so the copy outlives the payment row that account deletion
cascades away), then a `SET time_zone = '+08:00'` and an `INSERT IGNORE …
SELECT` that backfills the payments already paid. The `INSERT` is a seed of
sorts, which the rule forbids; it is allowed here because it replays
cleanly: the table's primary key is the payment's own `payment_id`, so
`INSERT IGNORE` skips every copy a failed or repeated run already made, and
`IF NOT EXISTS` skips the table. The `SET` only makes `DATE(paid_at)` the
Manila day whatever zone the runner's connection has; it is safe to repeat.

**`048_meal_suggestions.sql`** — one `ALTER TABLE foods` that adds
`suggest_meals` (a `SET` of the four meals, `''` = never suggested) and
`suggest_with_rice`, and drops `is_suggested` (004's flag, which nothing ever
read); then four `UPDATE`s that mark the starting list of 35 local Filipino
dishes on FitSync's own foods by exact name (View Local Filipino Meal
Suggestions, spec 2026-11-09). The `UPDATE`s are a seed of sorts, which the
rule forbids: they are here because a database that already has its foods
would otherwise get the columns with nothing suggested, and `seed-foods.js`
writes suggestions on insert only (after that they are the admin's). The
`UPDATE`s set the same values every time and are safe to repeat; the `ALTER`
is not. A run where the `ALTER` applied and an `UPDATE` failed hits
`ER_DUP_FIELDNAME` on re-run: check `DESCRIBE foods;` for `suggest_meals`, run
the file's four `UPDATE`s by hand, then record it with
`INSERT INTO schema_migrations (version) VALUES ('048_meal_suggestions.sql');`.

**`049_usual_rice_cups.sql`** — one `ALTER TABLE users ADD COLUMN
usual_rice_cups DECIMAL(2,1) NOT NULL DEFAULT 1.0`, the cups of white rice a
suggested plate carries for this user (`0`–`2` in halves; `PATCH /profile`
checks the set), 1 cup until they choose (Meal ideas round 1, spec
2026-11-13). Like `044` and `045`, the file is nothing but that one atomic
`ADD COLUMN`, so a failure inside it applied nothing and a failed run replays
cleanly; a run that applied it and was not recorded would hit
`ER_DUP_FIELDNAME` on re-run. Add a statement after it and that stops being
true.

**`050_food_contains.sql`** — one `ALTER TABLE foods` that adds `contains` (a
`SET` of the six food groups `pork`, `beef`, `chicken`, `fish`, `shellfish`
and `egg`, `''` = none), the groups a dish is often made with; then eleven
`UPDATE`s that tag 28 of the 35 starting suggestions on FitSync's own,
admin-untouched foods by exact name (Meal ideas round 2, spec 2026-11-13).
Suggestions skip a dish that contains a group the trainee avoids
(`users.avoid_foods`, 051). The `UPDATE`s are a seed of sorts, which the rule
forbids: they are here, as in 048, because a database that already has its
foods would otherwise get the column with nothing tagged, and `seed-foods.js`
writes `contains` on insert only (after that it is the admin's). The
`UPDATE`s set the same values every time and are safe to repeat; the `ALTER`
is not. A run where the `ALTER` applied and an `UPDATE` failed hits
`ER_DUP_FIELDNAME` on re-run: check `DESCRIBE foods;` for `contains`, run the
file's eleven `UPDATE`s by hand, then record it with
`INSERT INTO schema_migrations (version) VALUES ('050_food_contains.sql');`.

**`051_user_avoid_foods.sql`** — one `ALTER TABLE users ADD COLUMN
avoid_foods SET('pork','beef','chicken','fish','shellfish','egg') NOT NULL
DEFAULT ''`, the food groups this trainee avoids (`''` = none; `PATCH
/profile` checks the values), so suggestions skip dishes that contain any of
them (Meal ideas round 2, spec 2026-11-13). Like `044`, `045` and `049`, the
file is nothing but that one atomic `ADD COLUMN`, so a failure inside it
applied nothing and a failed run replays cleanly; a run that applied it and
was not recorded would hit `ER_DUP_FIELDNAME` on re-run. Add a statement after
it and that stops being true.

**`053_food_photo.sql`** — one `ALTER TABLE foods ADD COLUMN photo_key
VARCHAR(255) NULL`, the storage key of one of FitSync's own foods' photo
(`foods/<uuid>.jpg` or `.png`; `NULL` = none), shown beside its suggestion
(Meal ideas round 3, spec 2026-11-13). The files live in the storage folder,
which git ignores, never in the database. Like `044`, `045`, `049` and `051`,
the file is nothing but that one atomic `ADD COLUMN`, so a failure inside it
applied nothing and a failed run replays cleanly; a run that applied it and
was not recorded would hit `ER_DUP_FIELDNAME` on re-run. Add a statement after
it and that stops being true.

**`054_plan_replaced.sql`** — one `ALTER TABLE workout_plans` that adds
`replaced_plan_id INT NULL` and its foreign key `fk_workout_plans_replaced`
to `workout_plans(plan_id)` `ON DELETE SET NULL`: the plan a generated plan
replaced (`NULL` = it replaced nothing, or it was brought back by Undo), so
`POST /plans/restore-previous` restores exactly that one (AI Workout
Generator round 1, spec 2026-11-14). Old plans are deactivated, never
deleted, so the pointer has a row to name until the account goes. Like
`046`, the column and its constraint are one statement, so MySQL 8 applies
both or neither: a failure inside it applied nothing and a failed run
replays cleanly; a run that applied it and was not recorded would hit
`ER_DUP_FIELDNAME` on re-run. Add a statement after it, or split the column
and the constraint into two `ALTER`s, and that stops being true.

**If 007, 008, 011, 012, 013 or 017 fails partway through**, recovery is
manual:

1. Inspect the actual table shape to see exactly which statements already
   committed: for 007, `DESCRIBE users;`, `DESCRIBE injuries;`, `DESCRIBE
   user_injuries;`, `DESCRIBE exercises;`, and confirm whether
   `user_identities` exists; for 008, `DESCRIBE equipment;` and `SHOW INDEX
   FROM equipment;`; for 011, `DESCRIBE users;` to see whether
   `email_verified` already landed, and confirm whether `auth_tokens`
   exists; for 012, `DESCRIBE users;` for `weight_unit`; for 013,
   `DESCRIBE plan_exercises;` for `day_no` and `DESCRIBE workout_sessions;`
   for `plan_day_no`; for 017, `DESCRIBE workout_plans;` for `source`.
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
GRANT SELECT ON fitsync.exercise_preferences TO 'fitsync_ml'@'%';
FLUSH PRIVILEGES;
```

Migration 010 adds a fifth reference table. Migration 039 adds a sixth
reference table (`exercise_preferences`, the team's curated marks). The
service still reads no user row. `npm run seed:preferences` must run before
beginners can get plans: until that table has rows, the service refuses every
beginner plan with a 503 that names the step.

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
