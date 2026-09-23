-- How the user's previous session left them: the outcome label the injury-risk
-- work has never had. injury_risk_estimates stores a PREDICTION -- risk_level
-- and training_load_score -- and nothing in the schema recorded what actually
-- happened next, so no estimate could ever be checked against reality.
--
-- Asked at the start of the NEXT session rather than at the end of this one:
-- delayed-onset pain peaks 24-48 hours after training, and a question asked
-- while the user is still cooling down misses it.
--
-- One row per session (UNIQUE session_id), and only for a real answer. A
-- dismissed prompt writes nothing, so "nothing hurt" (pain_level = 'none') and
-- "never answered" (no row) stay permanently distinguishable -- a missing row
-- is missing data, never a negative.
--
-- CASCADE on session_id, unlike plan_swaps' SET NULL: a pain report about a
-- deleted session has no features left to train on.
--
-- injury_id reuses the 16 regions seed-injuries.js maintains, the vocabulary
-- the rules engine already filters on. It is NULL exactly when pain_level is
-- 'none', and ck_session_outcomes_region holds every writer to that, not only
-- the route.
CREATE TABLE IF NOT EXISTS session_outcomes (
  outcome_id  INT AUTO_INCREMENT PRIMARY KEY,
  user_id     INT NOT NULL,
  session_id  INT NOT NULL,
  pain_level  ENUM('none','mild','moderate','severe') NOT NULL,
  injury_id   INT NULL,
  reported_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_session_outcomes_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_session_outcomes_session
    FOREIGN KEY (session_id) REFERENCES workout_sessions(session_id) ON DELETE CASCADE,
  CONSTRAINT fk_session_outcomes_injury
    FOREIGN KEY (injury_id) REFERENCES injuries(injury_id) ON DELETE RESTRICT,
  CONSTRAINT ck_session_outcomes_region
    CHECK ((pain_level = 'none') = (injury_id IS NULL)),
  UNIQUE KEY uq_session_outcomes_session (session_id),
  KEY ix_session_outcomes_user (user_id),
  KEY ix_session_outcomes_injury (injury_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
