-- One shared training report: a link a coach opens, frozen at the moment it
-- was shared.
--
-- report_json holds the rendered numbers rather than a pointer to them.
-- Storing the window bounds and re-querying at read time would not be frozen:
-- editing or deleting a past session would silently change what a coach had
-- already been sent. Storing finished HTML would freeze the layout too, so the
-- page could never be improved.
--
-- token_hash holds SHA-256 of the shared link's token, never the token
-- itself -- the same policy 011_email_verification.sql states for auth_tokens,
-- and for the same reason: this token is the ONLY credential the page has
-- (there is no sign-in on the reading end) and it stays live for 30 days, so
-- a leaked table must yield nothing usable. The token itself is 32 bytes from
-- a CSPRNG, base64url, never derived from a user id or a timestamp, and is
-- returned to the sharer once and never read back out of the database.
-- UNIQUE because a collision would hand one coach another user's report.
--
-- Hex also sidesteps a collation trap the raw base64url token had: CHAR(43)
-- under utf8mb4_unicode_ci compares case-insensitively, so a case-mangled
-- token still matched. A hex digest has no case-distinct characters to mangle.
--
-- expires_at is written at creation rather than computed on read, so the
-- lifetime of a link is fixed by the rules in force when it was shared.
CREATE TABLE IF NOT EXISTS shared_reports (
  shared_report_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id      INT          NOT NULL,
  token_hash   CHAR(64)     NOT NULL,
  period       VARCHAR(16)  NOT NULL,
  window_start DATE         NOT NULL,
  window_end   DATE         NOT NULL,
  report_json  JSON         NOT NULL,
  created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at   TIMESTAMP    NOT NULL,
  CONSTRAINT fk_shared_reports_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  UNIQUE KEY uq_shared_reports_token_hash (token_hash),
  KEY ix_shared_reports_user (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
