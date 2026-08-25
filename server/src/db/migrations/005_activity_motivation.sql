CREATE TABLE IF NOT EXISTS activity_logs (
  activity_id     INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  log_date        DATE NOT NULL,
  steps           INT NOT NULL DEFAULT 0,
  calories_burned INT NOT NULL DEFAULT 0,
  distance_km     DECIMAL(6,2) NOT NULL DEFAULT 0,
  active_minutes  INT NOT NULL DEFAULT 0,
  CONSTRAINT fk_activity_logs_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_activity_logs_user_date (user_id, log_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS body_weight_logs (
  weight_log_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id       INT NOT NULL,
  weight_kg     DECIMAL(6,2) NOT NULL,
  log_date      DATE NOT NULL,
  CONSTRAINT fk_body_weight_logs_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_body_weight_logs_user_date (user_id, log_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS routine_items (
  routine_item_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  title           VARCHAR(255) NOT NULL,
  scheduled_time  TIME NULL,
  duration_min    INT NULL,
  item_date       DATE NOT NULL,
  is_done         BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_routine_items_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_routine_items_user_date (user_id, item_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS reminders (
  reminder_id   INT AUTO_INCREMENT PRIMARY KEY,
  user_id       INT NOT NULL,
  title         VARCHAR(255) NOT NULL,
  remind_at     DATETIME NOT NULL,
  lead_time_min INT NOT NULL DEFAULT 0,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_reminders_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_reminders_user_time (user_id, remind_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS streaks (
  streak_id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id            INT NOT NULL,
  current_streak     INT NOT NULL DEFAULT 0,
  best_streak        INT NOT NULL DEFAULT 0,
  last_activity_date DATE NULL,
  CONSTRAINT fk_streaks_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  UNIQUE KEY uq_streaks_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
