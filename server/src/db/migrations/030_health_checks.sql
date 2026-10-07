-- A user's own answers to the onboarding health check: a condition checklist
-- and three warning-sign questions. One row per user; no row means the user
-- has not answered, or chose "Don't save my answers".
--
-- Stored only with explicit consent: a positive check (any condition, or any
-- warning sign) is accepted by PUT /profile/health only when the user ticked
-- both the consent and the acknowledgement, and those moments are stamped in
-- consented_at / acknowledged_at. A clear check stores both as NULL, which
-- records "checked, nothing to report".
--
-- The plan generator never sees this table. It receives a single derived
-- boolean, healthCaution (db/profile.js getProfile).
--
-- CREATE TABLE IF NOT EXISTS only, within MIGRATIONS.md's rule.
CREATE TABLE IF NOT EXISTS health_checks (
  health_check_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  conditions      SET('high_blood_pressure','heart_condition','diabetes','asthma',
                      'pregnancy','recent_surgery','other') NOT NULL DEFAULT '',
  chest_pain      BOOLEAN NOT NULL,
  dizziness       BOOLEAN NOT NULL,
  supervised_only BOOLEAN NOT NULL,
  consented_at    TIMESTAMP NULL,
  acknowledged_at TIMESTAMP NULL,
  updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_health_checks_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  UNIQUE KEY uq_health_checks_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
