-- The upstream dataset gives each exercise exactly one equipment tag, so it can
-- record "this is a dumbbell exercise" but not "this needs a dumbbell AND a
-- bench". Two of the eight curated onboarding options -- 'bench' and
-- 'pull-up bar' -- are consequently referenced by zero catalogue rows, while 71
-- exercise names contain "bench" and 25 contain "pull-up". This table carries
-- the prerequisite that equipment_id cannot.
--
-- is_manual = 1 marks a human's correction. The seed never rewrites or deletes
-- those rows; it recomputes only is_manual = 0 rows.
CREATE TABLE IF NOT EXISTS exercise_equipment_requirements (
  requirement_id INT AUTO_INCREMENT PRIMARY KEY,
  exercise_id    INT NOT NULL,
  equipment_id   INT NOT NULL,
  is_manual      TINYINT(1) NOT NULL DEFAULT 0,
  CONSTRAINT fk_eer_exercise FOREIGN KEY (exercise_id)
    REFERENCES exercises(exercise_id) ON DELETE CASCADE,
  CONSTRAINT fk_eer_equipment FOREIGN KEY (equipment_id)
    REFERENCES equipment(equipment_id) ON DELETE RESTRICT,
  UNIQUE KEY uq_eer (exercise_id, equipment_id),
  INDEX idx_eer_equipment (equipment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- muscle_group records the muscle a movement TRAINS, not the structure it
-- LOADS. 'barbell deadlift' is tagged 'glutes', so excluding on muscle group
-- alone would strip a back-injured user's abs work and still prescribe them the
-- deadlift. Measured against the live catalogue, muscle-group exclusion alone
-- misses 18 of 19 deadlifts and 69 of 72 squats. This table is the second,
-- independent filter -- see the design, section 6.5.
--
-- Keyed on injury_id, not region_group. The three region groups are too coarse
-- to be safe: a wrist injury and a shoulder injury are both 'upper_body' but
-- rule out different exercises, and an elbow injury would match no group-level
-- pattern at all. seed-injuries.js defines 16 regions; this keys on those, which
-- also makes the table structurally identical to the requirements table above --
-- both resolve a curated name to a seeded id.
--
-- 'pattern' records WHY a row is here, so a reviewer can accept or reject a
-- whole movement class at once rather than row by row.
CREATE TABLE IF NOT EXISTS exercise_contraindications (
  contraindication_id INT AUTO_INCREMENT PRIMARY KEY,
  exercise_id         INT NOT NULL,
  injury_id           INT NOT NULL,
  pattern             VARCHAR(32) NOT NULL,
  is_manual           TINYINT(1) NOT NULL DEFAULT 0,
  CONSTRAINT fk_ec_exercise FOREIGN KEY (exercise_id)
    REFERENCES exercises(exercise_id) ON DELETE CASCADE,
  CONSTRAINT fk_ec_injury FOREIGN KEY (injury_id)
    REFERENCES injuries(injury_id) ON DELETE CASCADE,
  UNIQUE KEY uq_ec (exercise_id, injury_id),
  INDEX idx_ec_injury (injury_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
