-- The team's curated marks for each exercise (spec 2026-10-20-exercise-curation-design):
-- first / alternative choices for generated plans, search_only and never
-- for exercises plans must not suggest, and whether it suits a beginner.
-- is_manual = 1 is a later hand edit the seed never overwrites (the
-- exercise_categories pattern, migration 010).
CREATE TABLE IF NOT EXISTS exercise_preferences (
  exercise_id       INT PRIMARY KEY,
  priority          ENUM('first','alternative','search_only','never') NOT NULL,
  beginner_friendly BOOLEAN NOT NULL DEFAULT FALSE,
  is_manual         TINYINT(1) NOT NULL DEFAULT 0,
  CONSTRAINT fk_exercise_preferences_exercise FOREIGN KEY (exercise_id) REFERENCES exercises(exercise_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
