-- Six-digit codes emailed for verification and password reset, typed into
-- the app instead of following a link (see the email-codes design). A code
-- is short enough to guess, so it is guarded unlike the link tokens in
-- auth_tokens: one live code per user and purpose (a new one replaces the
-- old), a keyed hash that a leaked table cannot be reversed from without the
-- server secret, an attempt counter, and a short life.
--
-- auth_tokens stays: its rows are now unused, and shared reports reuse its
-- hashing helper.
CREATE TABLE IF NOT EXISTS auth_codes (
  user_id     INT NOT NULL,
  purpose     ENUM('verify_email','reset_password') NOT NULL,
  code_hash   CHAR(64) NOT NULL,
  expires_at  DATETIME NOT NULL,
  attempts    TINYINT UNSIGNED NOT NULL DEFAULT 0,
  created_at  DATETIME NOT NULL,
  PRIMARY KEY (user_id, purpose),
  CONSTRAINT fk_auth_codes_user FOREIGN KEY (user_id)
    REFERENCES users(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
