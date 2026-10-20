-- A FitSync food's type and its place in the seed list (spec
-- 2026-10-20-food-search-order-design). Search orders FitSync's own foods by
-- type -- home-cooked first, fast food and snacks near the end -- then by the
-- list's own everyday-first order. NULL for FatSecret copies and any food
-- outside the seed list. One atomic ALTER: a failure leaves nothing to replay
-- around.
ALTER TABLE foods
  ADD COLUMN food_type ENUM('home','fruit_veg','bread_kakanin','canned_instant','drink','street','snack_sweet','fast_food','condiment') NULL AFTER category,
  ADD COLUMN list_order INT NULL AFTER food_type;
