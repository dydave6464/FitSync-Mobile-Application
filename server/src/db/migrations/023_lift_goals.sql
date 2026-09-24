-- A lift target the user set: an exercise and a weight to reach. Progress is
-- never stored -- it is read from set_logs each time, so it cannot go stale.
--
-- goals (001) is not used for this: it has no exercise, and it stores its
-- progress as a number that would drift from the logs.
CREATE TABLE IF NOT EXISTS lift_goals (
  goal_id     INT AUTO_INCREMENT PRIMARY KEY,
  user_id     INT NOT NULL,
  exercise_id INT NOT NULL,
  target_kg   DECIMAL(6,2) NOT NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_lift_goals_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_lift_goals_exercise
    FOREIGN KEY (exercise_id) REFERENCES exercises(exercise_id),
  CONSTRAINT ck_lift_goals_target CHECK (target_kg BETWEEN 0.5 AND 999.99),
  KEY ix_lift_goals_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
