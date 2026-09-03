-- The catalogue records what muscle an exercise trains, not what kind of
-- movement it is. 55 of 1203 live rows are stretches, mobility drills or skill
-- holds, and the plan generator prescribed them at 3 sets of 8-12 reps. See the
-- design, section 3.
--
-- A table rather than a column on `exercises`: MIGRATIONS.md permits
-- CREATE TABLE IF NOT EXISTS and nothing else, so an ALTER would make this a
-- third documented exception alongside 007 and 008 -- the two files that are
-- not replay-safe.
--
-- No 'cardio' value: all 29 body_part='cardio' rows upstream carry
-- promote: false and never reach status='live'.
--
-- is_manual = 1 marks a human's judgement. seed-exercise-categories.js never
-- writes or deletes those rows.
CREATE TABLE IF NOT EXISTS exercise_categories (
  exercise_id INT NOT NULL PRIMARY KEY,
  category    ENUM('strength','stretch','mobility','other') NOT NULL,
  is_manual   TINYINT(1) NOT NULL DEFAULT 0,
  CONSTRAINT fk_exercise_categories_exercise FOREIGN KEY (exercise_id)
    REFERENCES exercises(exercise_id) ON DELETE CASCADE,
  INDEX idx_ec_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
