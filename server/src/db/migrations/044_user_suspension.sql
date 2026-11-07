-- Admin dashboard (spec 2026-11-07-admin-dashboard): a suspended trainee
-- can't sign in or use a token until an admin reinstates them. NULL = active.
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ADD COLUMN on a table 001
-- defined, so a failure inside it applied nothing (the 042 reasoning).
ALTER TABLE users ADD COLUMN suspended_at TIMESTAMP NULL DEFAULT NULL;
