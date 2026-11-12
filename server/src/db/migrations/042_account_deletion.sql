-- Account deletion and password change (spec 2026-11-06-account-deletion).
--
-- auth_tokens.purpose gains 'delete_account': the web deletion page (for
-- Google Play) confirms by a single-use, expiring emailed link, the same
-- mechanism as the old reset links. Appended at the END of the value list --
-- MySQL stores an enum as an index into it, so inserting in the middle would
-- change what every existing row means (as 014 and 028).
--
-- users.token_version is the account's token generation: every token carries
-- the generation it was signed for, and requireAuth accepts only the current
-- one. A password change or reset moves it on in the same UPDATE that writes
-- the new hash, signing out every older token. A generation, not a time: a
-- login that read the old hash before the change landed signs with the old
-- generation however late it finishes, and there is no same-second window.
-- Tokens signed before this column existed carry no generation and count as
-- 0, the starting value, so nobody is signed out by the migration itself.
--
-- POLICY EXCEPTION (MIGRATIONS.md). Both statements change tables 001 and 011
-- already defined. The MODIFY restates the whole column, so it replays
-- cleanly; the ADD COLUMN is last and one atomic statement, so a failure
-- inside it applied nothing (the 032 reasoning). Keep it last.
ALTER TABLE auth_tokens MODIFY COLUMN purpose
  ENUM('verify_email','reset_password','delete_account') NOT NULL;

ALTER TABLE users ADD COLUMN token_version INT UNSIGNED NOT NULL DEFAULT 0;
