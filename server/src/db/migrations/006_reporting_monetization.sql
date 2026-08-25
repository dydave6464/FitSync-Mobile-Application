CREATE TABLE IF NOT EXISTS progress_reports (
  report_id              INT AUTO_INCREMENT PRIMARY KEY,
  user_id                INT NOT NULL,
  period_start           DATE NOT NULL,
  period_end             DATE NOT NULL,
  include_volume         BOOLEAN NOT NULL DEFAULT TRUE,
  include_body_weight    BOOLEAN NOT NULL DEFAULT TRUE,
  include_prs            BOOLEAN NOT NULL DEFAULT TRUE,
  include_muscle_balance BOOLEAN NOT NULL DEFAULT FALSE,
  include_nutrition      BOOLEAN NOT NULL DEFAULT TRUE,
  pdf_url                VARCHAR(255) NULL,
  created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_progress_reports_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_progress_reports_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS advertisements (
  ad_id      INT AUTO_INCREMENT PRIMARY KEY,
  title      VARCHAR(255) NOT NULL,
  image_url  VARCHAR(255) NOT NULL,
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  added_by   INT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_advertisements_admin FOREIGN KEY (added_by) REFERENCES admins(admin_id) ON DELETE SET NULL,
  INDEX idx_advertisements_admin (added_by),
  INDEX idx_advertisements_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
