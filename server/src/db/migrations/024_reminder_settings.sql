-- What the phone reminds this user about, and when. The phone schedules the
-- reminders itself (local notifications); this row only follows the account
-- to a new phone or a reinstall. No row means the defaults below -- a read
-- never creates one.
--
-- The master switch is users.notifications_enabled, unchanged: when it is
-- off, nothing is scheduled whatever this row says.
CREATE TABLE IF NOT EXISTS reminder_settings (
  setting_id      INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  habits_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  habit_lead_min  TINYINT NOT NULL DEFAULT 15,
  workout_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  workout_time    TIME NOT NULL DEFAULT '07:00:00',
  checkin_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  checkin_time    TIME NOT NULL DEFAULT '07:00:00',
  CONSTRAINT fk_reminder_settings_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT ck_reminder_settings_lead CHECK (habit_lead_min IN (0, 5, 15, 30)),
  UNIQUE KEY uq_reminder_settings_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
