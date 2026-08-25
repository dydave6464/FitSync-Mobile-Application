CREATE TABLE IF NOT EXISTS morning_checkins (
  checkin_id      INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  checkin_date    DATE NOT NULL,
  sleep_quality   ENUM('poor','fair','good','excellent') NOT NULL,
  muscle_soreness ENUM('none','mild','moderate','severe') NOT NULL,
  energy          ENUM('very_low','low','moderate','high') NOT NULL,
  stress          ENUM('very_low','low','moderate','high') NOT NULL,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_morning_checkins_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  UNIQUE KEY uq_morning_checkins_user_date (user_id, checkin_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS injury_risk_estimates (
  estimate_id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id             INT NOT NULL,
  checkin_id          INT NOT NULL,
  risk_level          ENUM('low','moderate','high') NOT NULL,
  training_load_score DECIMAL(5,2) NULL,
  computed_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_injury_risk_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_injury_risk_checkin FOREIGN KEY (checkin_id) REFERENCES morning_checkins(checkin_id) ON DELETE CASCADE,
  INDEX idx_injury_risk_user (user_id),
  INDEX idx_injury_risk_checkin (checkin_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
