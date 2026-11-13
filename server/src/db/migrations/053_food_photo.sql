-- Meal ideas, round 3 (spec 2026-11-13-dish-photos-round-3-design): the
-- storage key of a FitSync food's photo (foods/<uuid>.jpg|png), NULL = none.
-- The files live in the storage folder (git-ignored), never in the database.
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ADD COLUMN on a table 004
-- defined, so a failure inside it applied nothing (the 049/051 reasoning).
ALTER TABLE foods ADD COLUMN photo_key VARCHAR(255) NULL AFTER contains;
