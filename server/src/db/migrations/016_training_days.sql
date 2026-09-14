-- The weekdays a user trains on.
--
-- A profile fact, not a plan one: savePlan deactivates every prior plan and
-- INSERTs a new row, so anything stored on workout_plans is erased on every
-- regenerate. "I cannot train Sundays" is true of a person's week, not of one
-- plan.
--
-- Display only. The rotation still advances on completed sessions
-- (nextPlanDayNo in src/db/sessions.js), so a missed Monday still costs a day
-- rather than a session. These rows say which days the strip may call missed.
--
-- No rows means no days chosen, which is a real and correct state: the week
-- strip renders it exactly as it did before this table existed. No backfill.
--
-- weekday is 1 = Monday .. 7 = Sunday, matching Dart's DateTime.weekday and
-- MySQL's WEEKDAY() + 1, so nothing has to translate.
--
-- The CHECK is the one days_per_week never had. That omission lets a plan
-- carry days_per_week = 0, which the client has to special-case rather than
-- render as "1 of 0".
CREATE TABLE IF NOT EXISTS user_training_days (
  user_training_day_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id  INT     NOT NULL,
  weekday  TINYINT NOT NULL,
  CONSTRAINT fk_user_training_days_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT ck_user_training_days_weekday CHECK (weekday BETWEEN 1 AND 7),
  UNIQUE KEY uq_user_training_day (user_id, weekday)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
