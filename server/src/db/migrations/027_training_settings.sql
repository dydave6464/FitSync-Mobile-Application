-- How long the logger rests between sets for this user. The phone runs the
-- countdown itself; this row only follows the account to a new phone or a
-- reinstall, the way users.weight_unit does. No row means the default below
-- -- a read never creates one.
--
-- A table of its own rather than a column on users, so this stays inside
-- MIGRATIONS.md's CREATE TABLE IF NOT EXISTS rule instead of adding a seventh
-- ALTER exception. Same shape as 024_reminder_settings.
--
-- 10 to 600 seconds is what the app offers: 30-second presets up to five
-- minutes, and a custom value up to ten.
CREATE TABLE IF NOT EXISTS training_settings (
  setting_id   INT AUTO_INCREMENT PRIMARY KEY,
  user_id      INT NOT NULL,
  rest_seconds SMALLINT NOT NULL DEFAULT 90,
  CONSTRAINT fk_training_settings_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT ck_training_settings_rest CHECK (rest_seconds BETWEEN 10 AND 600),
  UNIQUE KEY uq_training_settings_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
