-- A session's own exercise list.
--
-- A plan-backed session derives its list from plan_exercises via plan_id and
-- plan_day_no. A manually-logged session has no plan, so the exercises the
-- user picked have nowhere else to live -- set_logs records only sets actually
-- performed, and has neither an order column nor anywhere to put targets.
--
-- Written only for manual sessions. Plan-backed sessions keep deriving their
-- list, so nothing about that path changes.
CREATE TABLE IF NOT EXISTS session_exercises (
  session_exercise_id INT AUTO_INCREMENT PRIMARY KEY,
  session_id   INT NOT NULL,
  exercise_id  INT NOT NULL,
  order_no     INT NOT NULL,
  -- Defaults, not a prescription: the library collects no targets, and the
  -- client's PlanExercise model requires both fields non-null.
  target_sets  INT          NOT NULL DEFAULT 3,
  target_reps  VARCHAR(255) NOT NULL DEFAULT '8-12',
  CONSTRAINT fk_session_exercises_session FOREIGN KEY (session_id)
    REFERENCES workout_sessions(session_id) ON DELETE CASCADE,
  CONSTRAINT fk_session_exercises_exercise FOREIGN KEY (exercise_id)
    REFERENCES exercises(exercise_id) ON DELETE RESTRICT,
  UNIQUE KEY uq_session_exercises (session_id, exercise_id),
  INDEX idx_session_exercises_session (session_id, order_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
