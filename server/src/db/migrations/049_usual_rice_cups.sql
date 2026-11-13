-- Meal ideas, round 1 (spec 2026-11-13-meal-ideas-round-1-design): the cups
-- of white rice a suggested plate carries for this user -- 0, 0.5, 1, 1.5 or
-- 2 (PATCH /profile checks the set). 1 cup for everyone until they choose,
-- which is what every plate carried before.
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ADD COLUMN on a table 001
-- defined, so a failure inside it applied nothing (the 044/045 reasoning).
ALTER TABLE users ADD COLUMN usual_rice_cups DECIMAL(2,1) NOT NULL DEFAULT 1.0;
