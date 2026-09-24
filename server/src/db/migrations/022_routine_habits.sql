-- The Daily Routine checklist: habits the user sets up once, the weekdays each
-- repeats on, and a tick per habit per day.
--
-- routine_items (005) holds one row per item PER DATE and cannot say that a
-- habit repeats, so a daily habit there would have to be re-entered every day.
-- It is left in place, unused, for one-off items later.
--
-- A habit is deleted softly (is_active = FALSE): routine_checks is the history
-- a streak will one day be built from, and it should outlive the habit. Only
-- deleting the user removes it (CASCADE).
CREATE TABLE IF NOT EXISTS routine_habits (
  habit_id       INT AUTO_INCREMENT PRIMARY KEY,
  user_id        INT NOT NULL,
  title          VARCHAR(60) NOT NULL,
  scheduled_time TIME NULL,
  duration_min   INT NULL,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_routine_habits_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT ck_routine_habits_duration
    CHECK (duration_min IS NULL OR duration_min BETWEEN 1 AND 600),
  KEY ix_routine_habits_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per weekday a habit repeats on, 1 = Monday, as user_training_days
-- numbers them. Its own id rather than a composite key: schema-complete.test.js
-- refuses composite primary keys.
CREATE TABLE IF NOT EXISTS routine_habit_days (
  habit_day_id INT AUTO_INCREMENT PRIMARY KEY,
  habit_id     INT NOT NULL,
  weekday      TINYINT NOT NULL,
  CONSTRAINT fk_routine_habit_days_habit
    FOREIGN KEY (habit_id) REFERENCES routine_habits(habit_id) ON DELETE CASCADE,
  CONSTRAINT ck_routine_habit_days_weekday CHECK (weekday BETWEEN 1 AND 7),
  UNIQUE KEY uq_routine_habit_days (habit_id, weekday)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A habit ticked on a day. Unticking deletes the row; the UNIQUE key makes a
-- second tick a no-op rather than a duplicate.
CREATE TABLE IF NOT EXISTS routine_checks (
  check_id   INT AUTO_INCREMENT PRIMARY KEY,
  habit_id   INT NOT NULL,
  check_date DATE NOT NULL,
  checked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_routine_checks_habit
    FOREIGN KEY (habit_id) REFERENCES routine_habits(habit_id) ON DELETE CASCADE,
  UNIQUE KEY uq_routine_checks (habit_id, check_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
