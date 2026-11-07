-- Admin dashboard (spec 2026-11-07-admin-dashboard): a hidden FitSync food
-- leaves food search, Recents and Snap a meal; logging it by id still works.
-- NULL = shown.
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ADD COLUMN on a table 004
-- defined, so a failure inside it applied nothing (the 042 reasoning).
ALTER TABLE foods ADD COLUMN hidden_at TIMESTAMP NULL DEFAULT NULL;
