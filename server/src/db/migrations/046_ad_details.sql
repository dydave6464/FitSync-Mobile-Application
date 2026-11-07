-- Admin dashboard (spec 2026-11-07-admin-dashboard): FitSync's own ads.
-- link_url: optional https link the card opens. advertiser and amount_php:
-- who paid and how much (pesos), counted as ad revenue in the Manila month
-- the ad starts. starts_on/ends_on: the run dates (the API requires both for
-- every new ad; NULL only on rows from before this file). views/taps: counted
-- for free trainees while the ad is running. is_active = FALSE means paused.
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ALTER on a table 006 defined,
-- so a failure inside it applied nothing (the 042 reasoning).
ALTER TABLE advertisements
  ADD COLUMN link_url VARCHAR(500) NULL DEFAULT NULL,
  ADD COLUMN advertiser VARCHAR(120) NOT NULL DEFAULT '',
  ADD COLUMN amount_php DECIMAL(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN starts_on DATE NULL DEFAULT NULL,
  ADD COLUMN ends_on DATE NULL DEFAULT NULL,
  ADD COLUMN views INT UNSIGNED NOT NULL DEFAULT 0,
  ADD COLUMN taps INT UNSIGNED NOT NULL DEFAULT 0;
