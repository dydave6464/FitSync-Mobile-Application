-- AI Workout Generator round 1 (spec 2026-11-14-workout-generator-round-1):
-- which plan a generated plan replaced, so Undo restores exactly that one.
-- NULL = it replaced nothing (a first plan, a custom plan, or a plan already
-- restored by Undo). Old plans are never deleted (is_active = FALSE), so the
-- pointer always has a row to name until the user's account goes.
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ALTER on a table 002
-- defined, so a failure inside it applied nothing (the 049/051/053 reasoning).
ALTER TABLE workout_plans
  ADD COLUMN replaced_plan_id INT NULL,
  ADD CONSTRAINT fk_workout_plans_replaced
    FOREIGN KEY (replaced_plan_id) REFERENCES workout_plans(plan_id)
    ON DELETE SET NULL;
