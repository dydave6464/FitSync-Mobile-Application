-- Sugar and sodium logged with an entry (totals, like the macros beside them).
-- NULL means unknown: entries from before these columns, or foods that don't
-- list them.
ALTER TABLE meal_logs
  ADD COLUMN sugar_g DECIMAL(7,2) NULL AFTER fiber_g,
  ADD COLUMN sodium_mg DECIMAL(9,1) NULL AFTER sugar_g;
