-- View Local Filipino Meal Suggestions (spec
-- 2026-11-09-filipino-meal-suggestions-design): the meals a FitSync food is
-- suggested for ('' = never) and whether it is served as ulam with 1 cup of
-- white rice. is_suggested (004) goes: nothing ever read it.
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ALTER, then UPDATEs that mark
-- the starting list of 35 dishes on FitSync's own foods -- no FatSecret copy
-- (food_sources), nothing an admin added or edited (added_by) -- by exact
-- name (utf8mb4_bin: the column's own collation ignores case). After this the
-- admin owns these two columns; seed-foods.js writes them on insert only.
ALTER TABLE foods
  ADD COLUMN suggest_meals SET('breakfast','lunch','dinner','snack') NOT NULL DEFAULT '' AFTER list_order,
  ADD COLUMN suggest_with_rice BOOLEAN NOT NULL DEFAULT FALSE AFTER suggest_meals,
  DROP COLUMN is_suggested;

-- Breakfast plates that already carry their rice.
UPDATE foods f
   SET f.suggest_meals = 'breakfast', f.suggest_with_rice = FALSE
 WHERE f.added_by IS NULL
   AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Tapsilog', 'Bangsilog');

UPDATE foods f
   SET f.suggest_meals = 'breakfast', f.suggest_with_rice = TRUE
 WHERE f.added_by IS NULL
   AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN (
     'Tortang talong', 'Daing na bangus', 'Tinapang galunggong (smoked round scad)'
   );

UPDATE foods f
   SET f.suggest_meals = 'lunch,dinner', f.suggest_with_rice = TRUE
 WHERE f.added_by IS NULL
   AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN (
     'Tinolang manok', 'Sinigang na bangus (milkfish sour soup)', 'Sinigang na hipon', 'Sinigang na baboy',
     'Nilagang baka', 'Grilled bangus', 'Tilapia, grilled or steamed', 'Inihaw na tuna (grilled tuna steak)',
     'Paksiw na bangus (milkfish in vinegar)', 'Sarciadong isda (fish with tomato-egg sauce)',
     'Sutukil sinugba (grilled fish)', 'Ginataang tulingan (frigate tuna in coconut milk)', 'Chicken adobo',
     'Chicken afritada', 'Bistek tagalog', 'Lechon manok', 'Chicken inasal', 'Ginisang monggo', 'Pinakbet',
     'Chopsuey', 'Ginisang ampalaya with egg', 'Adobong kangkong'
   );

UPDATE foods f
   SET f.suggest_meals = 'snack', f.suggest_with_rice = FALSE
 WHERE f.added_by IS NULL
   AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN (
     'Saba banana, boiled', 'Kamote (sweet potato), boiled', 'Lakatan banana', 'Carabao mango, ripe',
     'Papaya fresh fruit', 'Pinya (pineapple)', 'Bayabas (guava)', 'Hard-boiled egg'
   );
