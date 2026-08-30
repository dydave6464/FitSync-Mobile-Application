-- The catalogue seed fills `equipment` from the upstream dataset's tags, which
-- are lowercase implement names ('body weight', 'leverage machine') and include
-- artifacts that are not gear ('assisted', 'weighted'). Onboarding needs a
-- curated, human-facing list instead. These columns are that presentation
-- layer; `seed-equipment.js` populates them.
--
-- is_user_selectable defaults to 0 deliberately: every existing row and every
-- future catalogue insert lands non-selectable, so a new upstream tag can never
-- leak into onboarding on its own.
ALTER TABLE equipment
  ADD COLUMN display_name        VARCHAR(64) NULL,
  ADD COLUMN display_order       INT NULL,
  ADD COLUMN is_user_selectable  TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN parent_equipment_id INT NULL,
  ADD CONSTRAINT fk_equipment_parent
      FOREIGN KEY (parent_equipment_id) REFERENCES equipment(equipment_id)
      ON DELETE SET NULL;

CREATE INDEX idx_equipment_selectable ON equipment (is_user_selectable, display_order);
