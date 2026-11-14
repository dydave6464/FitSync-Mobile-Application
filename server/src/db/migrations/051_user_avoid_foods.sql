-- Meal ideas, round 2 (spec 2026-11-13): the food groups this trainee avoids
-- ('' = none); suggestions skip dishes that contain any (foods.contains, 050).
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ADD COLUMN on a table 001
-- defined, so a failure inside it applied nothing (the 044/045/049 reasoning).
ALTER TABLE users ADD COLUMN avoid_foods SET('pork','beef','chicken','fish','shellfish','egg') NOT NULL DEFAULT '';
