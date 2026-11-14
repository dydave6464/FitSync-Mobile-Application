-- Meal ideas, round 2 (spec 2026-11-13): dishes a trainee asked not to be
-- suggested ("Don't suggest this"). Goes with the user (account deletion)
-- and with the food.
CREATE TABLE IF NOT EXISTS user_hidden_suggestions (
  user_id   INT NOT NULL,
  food_id   INT NOT NULL,
  hidden_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, food_id),
  INDEX idx_hidden_food (food_id),
  CONSTRAINT fk_hidden_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_hidden_food FOREIGN KEY (food_id) REFERENCES foods(food_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
