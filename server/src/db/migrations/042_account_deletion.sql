-- Account deletion and password change (spec 2026-11-06-account-deletion).
--
-- auth_tokens.purpose gains 'delete_account': the web deletion page (for
-- Google Play) confirms by a single-use, expiring emailed link, the same
-- mechanism as the old reset links. Appended at the END of the value list --
-- MySQL stores an enum as an index into it, so inserting in the middle would
-- change what every existing row means (as 014 and 028).
--
-- users.tokens_valid_after is the sign-out cutoff: requireAuth rejects a
-- token issued (whole seconds) before it. A password change or reset sets it
-- to now. NULL means no cutoff.
--
-- POLICY EXCEPTION (MIGRATIONS.md). Both statements change tables 001 and 011
-- already defined. The MODIFY restates the whole column, so it replays
-- cleanly; the ADD COLUMN is last and one atomic statement, so a failure
-- inside it applied nothing (the 032 reasoning). Keep it last.
ALTER TABLE auth_tokens MODIFY COLUMN purpose
  ENUM('verify_email','reset_password','delete_account') NOT NULL;

ALTER TABLE users ADD COLUMN tokens_valid_after TIMESTAMP NULL DEFAULT NULL;
