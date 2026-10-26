-- Snap a meal (spec 2026-10-21-snap-a-meal-design): one row per photo the
-- AI looked at, one per item it suggested. The photo itself is never stored,
-- and no column here could hold it. status 'failed' (the AI busy or down)
-- never counts against the daily limit. On logging, each suggestion's
-- outcome says whether the user kept it, swapped it or removed it -- the
-- "first guess kept X% of the time" figure. The old food_recognitions table
-- (004) is left unused.
CREATE TABLE IF NOT EXISTS photo_recognitions (
  recognition_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id        INT NOT NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  item_count     INT NOT NULL DEFAULT 0,
  status         ENUM('recognised','empty','failed') NOT NULL,
  logged_at      TIMESTAMP NULL DEFAULT NULL,
  CONSTRAINT fk_photo_recognitions_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_photo_recognitions_user_created (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- suggested_food_id NULL: an item not in FitSync's list (suggested_name is
-- what the AI called it, and suggested_servings is NULL). logged_food_id is
-- the food actually logged for it (NULL for a manual entry or a removal).
CREATE TABLE IF NOT EXISTS photo_recognition_items (
  item_id              INT AUTO_INCREMENT PRIMARY KEY,
  recognition_id       INT NOT NULL,
  item_order           INT NOT NULL,
  suggested_food_id    INT NULL,
  suggested_name       VARCHAR(255) NOT NULL,
  confidence           DECIMAL(4,3) NULL,
  suggested_servings   DECIMAL(5,2) NULL,
  alternative_food_ids JSON NOT NULL,
  outcome              ENUM('pending','kept','swapped','removed') NOT NULL DEFAULT 'pending',
  logged_food_id       INT NULL,
  meal_log_id          INT NULL,
  CONSTRAINT fk_photo_items_recognition FOREIGN KEY (recognition_id) REFERENCES photo_recognitions(recognition_id) ON DELETE CASCADE,
  CONSTRAINT fk_photo_items_food FOREIGN KEY (suggested_food_id) REFERENCES foods(food_id) ON DELETE SET NULL,
  CONSTRAINT fk_photo_items_meal_log FOREIGN KEY (meal_log_id) REFERENCES meal_logs(meal_log_id) ON DELETE SET NULL,
  INDEX idx_photo_items_recognition (recognition_id),
  INDEX idx_photo_items_food (suggested_food_id),
  INDEX idx_photo_items_meal_log (meal_log_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
