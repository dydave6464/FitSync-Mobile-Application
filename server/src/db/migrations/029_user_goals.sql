-- Every goal a user ticked, in the order they appear on the goal screen.
-- users.main_goal keeps its column and now means the MAIN FOCUS among these:
-- the one goal that sets a plan's sets and reps. Keeping the focus there means
-- every existing reader (the plan generator, the profile nudge, the plan
-- description) is untouched by a user choosing several goals.
--
-- No backfill: an account with main_goal and no rows here reads back as
-- [main_goal] (db/profile.js getProfile).
--
-- CREATE TABLE IF NOT EXISTS only, within MIGRATIONS.md's rule.
CREATE TABLE IF NOT EXISTS user_goals (
  user_goal_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id      INT NOT NULL,
  goal         ENUM('lose_weight','build_muscle','improve_endurance','general_fitness') NOT NULL,
  position     TINYINT NOT NULL,
  CONSTRAINT fk_user_goals_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  UNIQUE KEY uq_user_goals_user_goal (user_id, goal)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
