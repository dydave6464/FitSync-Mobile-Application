CREATE TABLE IF NOT EXISTS foods (
  food_id      INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(255) NOT NULL,
  category     ENUM('filipino','international') NOT NULL DEFAULT 'filipino',
  serving_desc VARCHAR(255) NULL,
  calories     INT NOT NULL,
  protein_g    DECIMAL(5,2) NOT NULL DEFAULT 0,
  carbs_g      DECIMAL(5,2) NOT NULL DEFAULT 0,
  fat_g        DECIMAL(5,2) NOT NULL DEFAULT 0,
  is_suggested BOOLEAN NOT NULL DEFAULT FALSE,
  added_by     INT NULL,
  CONSTRAINT fk_foods_admin FOREIGN KEY (added_by) REFERENCES admins(admin_id) ON DELETE SET NULL,
  INDEX idx_foods_admin (added_by),
  INDEX idx_foods_category (category),
  INDEX idx_foods_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS meal_logs (
  meal_log_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id     INT NOT NULL,
  food_id     INT NULL,
  custom_name VARCHAR(255) NULL,
  meal_type   ENUM('breakfast','lunch','dinner','snack') NOT NULL,
  servings    DECIMAL(5,2) NOT NULL DEFAULT 1,
  calories    INT NOT NULL,
  protein_g   DECIMAL(5,2) NOT NULL DEFAULT 0,
  carbs_g     DECIMAL(5,2) NOT NULL DEFAULT 0,
  fat_g       DECIMAL(5,2) NOT NULL DEFAULT 0,
  logged_via  ENUM('search','manual','photo') NOT NULL,
  log_date    DATE NOT NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_meal_logs_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_meal_logs_food FOREIGN KEY (food_id) REFERENCES foods(food_id) ON DELETE RESTRICT,
  CONSTRAINT chk_meal_logs_food_or_name CHECK (food_id IS NOT NULL OR custom_name IS NOT NULL),
  INDEX idx_meal_logs_user_date (user_id, log_date),
  INDEX idx_meal_logs_food (food_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS food_recognitions (
  recognition_id    INT AUTO_INCREMENT PRIMARY KEY,
  user_id           INT NOT NULL,
  suggested_food_id INT NULL,
  meal_log_id       INT NULL,
  photo_url         VARCHAR(255) NOT NULL,
  match_confidence  DECIMAL(4,3) NULL,
  is_confirmed      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_food_recognitions_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_food_recognitions_food FOREIGN KEY (suggested_food_id) REFERENCES foods(food_id) ON DELETE SET NULL,
  CONSTRAINT fk_food_recognitions_meal_log FOREIGN KEY (meal_log_id) REFERENCES meal_logs(meal_log_id) ON DELETE SET NULL,
  INDEX idx_food_recognitions_user (user_id),
  INDEX idx_food_recognitions_food (suggested_food_id),
  INDEX idx_food_recognitions_meal_log (meal_log_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
