-- Meal ideas, round 2 (spec 2026-11-13-meal-preferences-round-2-design): the
-- food groups a FitSync food is OFTEN made with ('' = none), so suggestions
-- can skip dishes a trainee avoids (users.avoid_foods, 051).
-- POLICY EXCEPTION (MIGRATIONS.md): one atomic ALTER on a table 004 defined,
-- then UPDATEs that tag the starting list on FitSync's own, admin-untouched
-- foods by exact name (utf8mb4_bin), as 048 marks suggestions. After this the
-- admin owns the column; seed-foods.js writes it on insert only.
ALTER TABLE foods
  ADD COLUMN contains SET('pork','beef','chicken','fish','shellfish','egg') NOT NULL DEFAULT '' AFTER suggest_with_rice;

UPDATE foods f SET f.contains = 'beef,egg'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Tapsilog');

UPDATE foods f SET f.contains = 'fish,egg'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Bangsilog', 'Sarciadong isda (fish with tomato-egg sauce)');

UPDATE foods f SET f.contains = 'chicken'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Chicken adobo', 'Tinolang manok', 'Chicken inasal', 'Lechon manok', 'Chicken afritada');

UPDATE foods f SET f.contains = 'pork'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Sinigang na baboy', 'Ginisang monggo', 'Adobong kangkong');

UPDATE foods f SET f.contains = 'shellfish'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Sinigang na hipon');

UPDATE foods f SET f.contains = 'beef'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Nilagang baka', 'Bistek tagalog');

UPDATE foods f SET f.contains = 'pork,shellfish'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Pinakbet');

UPDATE foods f SET f.contains = 'pork,shellfish,egg'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Chopsuey');

UPDATE foods f SET f.contains = 'pork,egg'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Ginisang ampalaya with egg');

UPDATE foods f SET f.contains = 'egg'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN ('Tortang talong', 'Hard-boiled egg');

UPDATE foods f SET f.contains = 'fish'
 WHERE f.added_by IS NULL AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
   AND f.name COLLATE utf8mb4_bin IN (
     'Grilled bangus', 'Daing na bangus', 'Paksiw na bangus (milkfish in vinegar)',
     'Sinigang na bangus (milkfish sour soup)', 'Tilapia, grilled or steamed', 'Sutukil sinugba (grilled fish)',
     'Ginataang tulingan (frigate tuna in coconut milk)', 'Tinapang galunggong (smoked round scad)',
     'Inihaw na tuna (grilled tuna steak)'
   );
