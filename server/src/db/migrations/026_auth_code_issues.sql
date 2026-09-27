-- One row per code issued, so issueCode can cap how many codes an account
-- gets per purpose in a rolling day. The count cannot live on auth_codes:
-- that row is deleted when a code is used or found expired, and an attacker
-- could reset a counter kept there simply by letting a code expire.
-- Rows older than a day are pruned as new codes are issued.
CREATE TABLE IF NOT EXISTS auth_code_issues (
  issue_id    INT AUTO_INCREMENT PRIMARY KEY,
  user_id     INT NOT NULL,
  purpose     ENUM('verify_email','reset_password') NOT NULL,
  issued_at   DATETIME NOT NULL,
  INDEX idx_auth_code_issues_user (user_id, purpose, issued_at),
  CONSTRAINT fk_auth_code_issues_user FOREIGN KEY (user_id)
    REFERENCES users(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
