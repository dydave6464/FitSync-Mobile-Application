-- Dietary fiber per serving (spec 2026-10-14-nutrition-fiber-design). NULL
-- means unknown -- a FatSecret search item or an older food -- and is never
-- read as 0. One atomic ALTER: a failure leaves nothing to replay around.
ALTER TABLE foods ADD COLUMN fiber_g DECIMAL(5,2) NULL AFTER fat_g;
