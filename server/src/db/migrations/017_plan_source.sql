-- Where a plan came from.
--
-- The generator was the only thing that could create one, so every existing
-- row is 'generated' and the DEFAULT says so without a backfill.
--
-- 'custom' means the user built it out of workouts they actually completed
-- (POST /plans/from-session). The distinction earns its place by guarding
-- regeneration: savePlan deactivates the active plan inside its transaction,
-- which is correct for a plan a machine produced and destructive for one a
-- person assembled a day at a time.
--
-- On workout_plans rather than on a join table because it is a fact about the
-- plan itself, and because savePlan already rewrites this row on every
-- regenerate -- there is nowhere cheaper to put it.
ALTER TABLE workout_plans
  ADD COLUMN source ENUM('generated','custom') NOT NULL DEFAULT 'generated';
