-- The food log, sub-project 1 (spec 2026-10-09-nutrition-tracker-core-design).
--
-- Replay-safe by ordering (see MIGRATIONS.md): the CREATE ... IF NOT EXISTS
-- comes first and the one ALTER comes last. A failure before the ALTER
-- replays cleanly, and MySQL 8 DDL is atomic, so a failure inside the ALTER
-- leaves nothing half-applied to retry around.

-- Which foods rows are copies of a FatSecret food. A seeded food has no row
-- here, which is how search tells the two apart, and the unique key is what
-- stops two users logging the same FatSecret food from copying it twice.
CREATE TABLE IF NOT EXISTS food_sources (
  food_id     INT PRIMARY KEY,
  provider    ENUM('fatsecret') NOT NULL,
  external_id VARCHAR(64) NOT NULL,
  CONSTRAINT fk_food_sources_food FOREIGN KEY (food_id) REFERENCES foods(food_id) ON DELETE CASCADE,
  UNIQUE KEY uq_food_sources_external (provider, external_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- serving_desc: a manual entry's "serving size" text; catalogue entries read
-- their food's. The macros widen because a row stores totals: 20 servings of
-- a 500 g manual entry is 10,000 g, past DECIMAL(5,2)'s 999.99.
ALTER TABLE meal_logs
  ADD COLUMN serving_desc VARCHAR(255) NULL AFTER custom_name,
  MODIFY protein_g DECIMAL(7,2) NOT NULL DEFAULT 0,
  MODIFY carbs_g   DECIMAL(7,2) NOT NULL DEFAULT 0,
  MODIFY fat_g     DECIMAL(7,2) NOT NULL DEFAULT 0;
