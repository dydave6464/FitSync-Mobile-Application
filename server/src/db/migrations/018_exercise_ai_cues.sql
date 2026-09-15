-- Coaching cues written for a movement AND an injured region, cached so they
-- are written once and then read forever.
--
-- Keyed on the PAIR, not the user. How to press safely with a bad shoulder is a
-- property of the movement and the joint, not of the person's age or goal, so
-- two users with a shoulder injury share one row and the second pays nothing.
-- That is what makes a rate-limited free tier a non-issue here: a realistic
-- session generates one to three cues once, ever, and every later session --
-- and every other user -- reads MySQL.
--
-- Not keyed on side. user_injuries records a left or a right shoulder; the
-- advice for the two is identical.
--
-- No expiry. Movement mechanics do not change, so a row stays correct for as
-- long as it exists -- which is also why what goes IN is validated before the
-- insert, in services/cues. A malformed generation stored once is stored
-- forever, and nothing sweeps it up later.
--
-- title and detail are sized to match that validator exactly (120 / 400). If
-- either side moves, move both: a column narrower than the validator truncates
-- mid-sentence what the validator was willing to accept.
--
-- `model` exists so a future model swap can find and re-warm the rows the old
-- one wrote, selectively, instead of dropping the table.
CREATE TABLE IF NOT EXISTS exercise_ai_cues (
  ai_cue_id    INT AUTO_INCREMENT PRIMARY KEY,
  exercise_id  INT NOT NULL,
  injury_id    INT NOT NULL,
  order_no     INT NOT NULL,
  title        VARCHAR(120) NOT NULL,
  detail       VARCHAR(400) NOT NULL,
  model        VARCHAR(64)  NOT NULL,
  generated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_eac_exercise FOREIGN KEY (exercise_id)
    REFERENCES exercises(exercise_id) ON DELETE CASCADE,
  CONSTRAINT fk_eac_injury FOREIGN KEY (injury_id)
    REFERENCES injuries(injury_id) ON DELETE CASCADE,
  UNIQUE KEY uq_eac (exercise_id, injury_id, order_no),
  INDEX idx_eac_pair (exercise_id, injury_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
