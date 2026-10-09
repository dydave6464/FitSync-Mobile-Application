-- Which exercises a free user has had AI cues for, per Philippine day. Pro
-- unlocks "unlimited AI-generated coaching cues" (manuscript), so a free user
-- gets FREE_DAILY_AI_CUES different exercises a day (src/db/ai-cue-allowance.js).
-- Re-opening one already counted that day costs nothing, which the unique key
-- makes a no-op insert. Pro users are never written here.
--
-- used_on is CURDATE() in the session's time zone, which src/db/pool.js sets
-- to +08:00 on every connection.
--
-- CREATE TABLE IF NOT EXISTS only, within MIGRATIONS.md's rule.
CREATE TABLE IF NOT EXISTS ai_cue_uses (
  ai_cue_use_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id       INT NOT NULL,
  used_on       DATE NOT NULL,
  exercise_id   INT NOT NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_ai_cue_uses_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_ai_cue_uses_exercise
    FOREIGN KEY (exercise_id) REFERENCES exercises(exercise_id) ON DELETE CASCADE,
  UNIQUE KEY uq_ai_cue_uses_user_day_exercise (user_id, used_on, exercise_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
