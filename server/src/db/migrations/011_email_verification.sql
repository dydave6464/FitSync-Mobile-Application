-- Registration previously accepted any address with no proof of ownership:
-- `requireString` checks type and length only, so someone.else@gmail.com
-- registered as readily as a real address. Verification is a HARD gate --
-- an unverified account is issued no token and cannot sign in -- so this
-- column decides access, not merely data quality. See the design, section 3.
--
-- POLICY EXCEPTION. MIGRATIONS.md permits CREATE TABLE IF NOT EXISTS and
-- nothing else. The ALTER below makes this the third deliberate exception
-- after 007 and 008, for the identical reason: it changes a table 001 already
-- defined and that is already applied on existing databases, where an in-place
-- edit to 001 would be silently invisible. Like those two it is NOT
-- replay-safe -- a partial failure leaves the ALTER committed and a re-run
-- hits ER_DUP_FIELDNAME. Recovery steps are in MIGRATIONS.md.
ALTER TABLE users ADD COLUMN email_verified TINYINT(1) NOT NULL DEFAULT 0;

-- One table serves verification and password reset. They need identical
-- machinery -- a single-use, expiring, purpose-bound credential -- and
-- splitting them would mean maintaining that machinery twice.
--
-- token_hash is the PRIMARY KEY and holds SHA-256 of the emailed value, never
-- the value itself. A database leak therefore yields nothing usable: an
-- outstanding reset token is a live account takeover, so it earns the same
-- treatment as password_hash.
CREATE TABLE IF NOT EXISTS auth_tokens (
  token_hash  CHAR(64) NOT NULL PRIMARY KEY,
  user_id     INT NOT NULL,
  purpose     ENUM('verify_email','reset_password') NOT NULL,
  expires_at  DATETIME NOT NULL,
  consumed_at DATETIME NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_auth_tokens_user FOREIGN KEY (user_id)
    REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_auth_tokens_user (user_id, purpose)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
