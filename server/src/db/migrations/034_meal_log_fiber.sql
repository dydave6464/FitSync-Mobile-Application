-- Fiber logged with an entry (a total, like the macros beside it). NULL means
-- unknown: entries from before this column, or foods whose fiber isn't listed.
ALTER TABLE meal_logs ADD COLUMN fiber_g DECIMAL(7,2) NULL AFTER fat_g;
