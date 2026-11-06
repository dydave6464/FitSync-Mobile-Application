-- Single-food logs made safe to retry (server round part 2, NU-4): the app
-- makes one clientId per log and sends it again on Try again; a repeat gets
-- the entry already saved, never a second one. Deleting the entry deletes its
-- id (CASCADE); deleting the account deletes both.
CREATE TABLE IF NOT EXISTS meal_log_client_ids (
  user_id     INT NOT NULL,
  client_id   CHAR(36) NOT NULL,
  meal_log_id INT NOT NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, client_id),
  UNIQUE KEY uq_meal_log_client_ids_entry (meal_log_id),
  CONSTRAINT fk_meal_log_client_ids_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_meal_log_client_ids_entry FOREIGN KEY (meal_log_id) REFERENCES meal_logs(meal_log_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
