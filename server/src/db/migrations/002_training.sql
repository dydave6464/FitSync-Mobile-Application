CREATE TABLE IF NOT EXISTS exercises (
  exercise_id   INT AUTO_INCREMENT PRIMARY KEY,
  source_id     VARCHAR(16) NULL,
  name          VARCHAR(255) NOT NULL,
  muscle_group  VARCHAR(255) NOT NULL,
  equipment_id  INT NULL,
  animation_url VARCHAR(255) NULL,
  thumbnail_url VARCHAR(255) NULL,
  status        ENUM('pending','live') NOT NULL DEFAULT 'pending',
  reviewed_by   INT NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_exercises_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(equipment_id) ON DELETE RESTRICT,
  CONSTRAINT fk_exercises_reviewer FOREIGN KEY (reviewed_by) REFERENCES admins(admin_id) ON DELETE SET NULL,
  UNIQUE KEY uq_exercises_source (source_id),
  INDEX idx_exercises_equipment (equipment_id),
  INDEX idx_exercises_reviewer (reviewed_by),
  INDEX idx_exercises_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS coaching_cues (
  cue_id      INT AUTO_INCREMENT PRIMARY KEY,
  exercise_id INT NOT NULL,
  order_no    INT NOT NULL,
  cue_text    VARCHAR(500) NOT NULL,
  CONSTRAINT fk_coaching_cues_exercise FOREIGN KEY (exercise_id) REFERENCES exercises(exercise_id) ON DELETE CASCADE,
  INDEX idx_coaching_cues_exercise (exercise_id, order_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS workout_plans (
  plan_id            INT AUTO_INCREMENT PRIMARY KEY,
  user_id            INT NOT NULL,
  name               VARCHAR(255) NOT NULL,
  split_style        ENUM('full_body','upper_lower','push_pull_legs','bro_split') NOT NULL,
  days_per_week      INT NOT NULL,
  session_length_min INT NOT NULL,
  week_no            INT NOT NULL DEFAULT 1,
  is_active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_workout_plans_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_workout_plans_user (user_id, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS plan_exercises (
  plan_exercise_id INT AUTO_INCREMENT PRIMARY KEY,
  plan_id          INT NOT NULL,
  exercise_id      INT NOT NULL,
  order_no         INT NOT NULL,
  target_sets      INT NOT NULL,
  target_reps      VARCHAR(255) NOT NULL,
  CONSTRAINT fk_plan_exercises_plan FOREIGN KEY (plan_id) REFERENCES workout_plans(plan_id) ON DELETE CASCADE,
  CONSTRAINT fk_plan_exercises_exercise FOREIGN KEY (exercise_id) REFERENCES exercises(exercise_id) ON DELETE RESTRICT,
  INDEX idx_plan_exercises_plan (plan_id, order_no),
  INDEX idx_plan_exercises_exercise (exercise_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS workout_sessions (
  session_id      INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  plan_id         INT NULL,
  session_date    DATE NOT NULL,
  duration_min    INT NULL,
  total_volume_kg DECIMAL(10,2) NULL,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_workout_sessions_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_workout_sessions_plan FOREIGN KEY (plan_id) REFERENCES workout_plans(plan_id) ON DELETE SET NULL,
  INDEX idx_workout_sessions_user_date (user_id, session_date),
  INDEX idx_workout_sessions_plan (plan_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS set_logs (
  set_log_id   INT AUTO_INCREMENT PRIMARY KEY,
  session_id   INT NOT NULL,
  exercise_id  INT NOT NULL,
  set_number   INT NOT NULL,
  weight_kg    DECIMAL(6,2) NULL,
  reps         INT NULL,
  is_completed BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_set_logs_session FOREIGN KEY (session_id) REFERENCES workout_sessions(session_id) ON DELETE CASCADE,
  CONSTRAINT fk_set_logs_exercise FOREIGN KEY (exercise_id) REFERENCES exercises(exercise_id) ON DELETE RESTRICT,
  UNIQUE KEY uq_set_logs_session_exercise_set (session_id, exercise_id, set_number),
  INDEX idx_set_logs_session (session_id),
  INDEX idx_set_logs_exercise (exercise_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
