-- Sugar (g) and sodium (mg) per serving (spec 2026-10-15-sugar-sodium-ph-foods-design).
-- NULL means unknown -- a FatSecret search item or a food that doesn't list
-- them -- and is never read as 0. One atomic ALTER: a failure leaves nothing
-- to replay around.
ALTER TABLE foods
  ADD COLUMN sugar_g DECIMAL(5,2) NULL AFTER fiber_g,
  ADD COLUMN sodium_mg DECIMAL(7,1) NULL AFTER sugar_g;
