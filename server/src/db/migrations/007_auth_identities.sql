-- Auth identities and the columns the onboarding slice needs.
-- New file: the runner will not replay an edited migration.

CREATE TABLE IF NOT EXISTS user_identities (
  user_identity_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id          INT NOT NULL,
  provider         ENUM('google') NOT NULL,
  provider_subject VARCHAR(255) NOT NULL,
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_user_identities_user FOREIGN KEY (user_id)
    REFERENCES users(user_id) ON DELETE CASCADE,
  UNIQUE KEY uq_identity_provider_subject (provider, provider_subject),
  INDEX idx_user_identities_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A Google-only account has no password at all.
ALTER TABLE users MODIFY COLUMN password_hash VARCHAR(255) NULL;

-- Settled in spec review: the mockup's four goals win over the data dictionary.
ALTER TABLE users MODIFY COLUMN main_goal
  ENUM('lose_weight','build_muscle','improve_endurance','general_fitness') NULL;

ALTER TABLE users
  ADD COLUMN notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN onboarding_completed_at TIMESTAMP NULL;

-- is_lateral tells the UI whether to offer a side at all; a neck has none.
ALTER TABLE injuries
  ADD COLUMN is_lateral BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN region_group VARCHAR(32) NOT NULL DEFAULT 'other';

ALTER TABLE user_injuries
  ADD COLUMN side ENUM('left','right','both') NULL;

-- Present in the source dataset, discarded at seed time until now. Every
-- injury-filtering approach in the spec needs it. See spec section 6a.
ALTER TABLE exercises ADD COLUMN body_part VARCHAR(64) NULL;
