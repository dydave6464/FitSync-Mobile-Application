-- What a user rejected, and what they were choosing from when they rejected it.
--
-- swapPlanExercise (src/db/plan-swap.js) is a single
-- `UPDATE plan_exercises SET exercise_id = ?`. Before this table the id it
-- overwrote was simply gone: a database in which a thousand users rejected an
-- exercise was byte-identical to one in which nobody ever opened the swap
-- sheet. A swap is a deliberate, user-initiated rejection -- a far cleaner
-- signal than an unexplained skip, a label that in the current data is mostly
-- seed-demo.js arithmetic.
--
-- Rows are written best-effort and only AFTER the UPDATE succeeds. Losing a
-- label beats recording one for a swap that did not happen, and a failure in
-- this table must never fail a user's swap.
--
-- plan_id and plan_exercise_id are context only, both nullable and both
-- ON DELETE SET NULL rather than CASCADE: plan_exercises rows are rewritten in
-- place and cascade away with their plan, and the label has to outlive both.
--
-- muscle_group is denormalised deliberately. It records what the SLOT meant at
-- the time, which stays true even if the exercise is recategorised later.
--
-- There is no `reason` column yet. Capturing WHY someone swapped needs a
-- question in the client; adding it later as a nullable column leaves every row
-- written before it perfectly valid, whereas not capturing the swap at all is
-- the loss that cannot be undone.
CREATE TABLE IF NOT EXISTS plan_swaps (
  swap_id              INT AUTO_INCREMENT PRIMARY KEY,
  user_id              INT          NOT NULL,
  plan_id              INT          NULL,
  plan_exercise_id     INT          NULL,
  rejected_exercise_id INT          NOT NULL,
  chosen_exercise_id   INT          NOT NULL,
  muscle_group         VARCHAR(255) NOT NULL,
  swapped_at           TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_plan_swaps_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_plan_swaps_plan
    FOREIGN KEY (plan_id) REFERENCES workout_plans(plan_id) ON DELETE SET NULL,
  CONSTRAINT fk_plan_swaps_plan_exercise
    FOREIGN KEY (plan_exercise_id) REFERENCES plan_exercises(plan_exercise_id)
    ON DELETE SET NULL,
  CONSTRAINT fk_plan_swaps_rejected
    FOREIGN KEY (rejected_exercise_id) REFERENCES exercises(exercise_id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_plan_swaps_chosen
    FOREIGN KEY (chosen_exercise_id) REFERENCES exercises(exercise_id)
    ON DELETE RESTRICT,
  KEY ix_plan_swaps_user (user_id, swapped_at),
  KEY ix_plan_swaps_rejected (rejected_exercise_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The choice set: every alternative the swap sheet had on screen, in the order
-- it showed them.
--
-- Without this a rejection count is confounded by exposure -- an exercise that
-- is rarely offered looks exactly like one nobody wants. Recording what was
-- passed over turns each swap into a choice among known alternatives, which is
-- what a learning-to-rank model trains on, and ml/app/ranker.py's slot is a
-- re-ranker by construction: it receives Sequence[Candidate] with no profile
-- attached, so a GLOBAL ordering of exercises is the only thing it can learn.
--
-- position_no is 1-based and is itself signal: listAlternatives orders
-- equipment the user actually selected ahead of the body-weight fallback.
--
-- The set is re-derived at swap time rather than carried over from the GET that
-- built the sheet, which is what keeps this server-side -- no new API contract
-- and no client change. The imprecision that buys: a swap made from a SEARCHED
-- sheet (`q`) or a bodyweight-only one records the DEFAULT sheet rather than
-- what was literally on screen.
CREATE TABLE IF NOT EXISTS plan_swap_alternatives (
  swap_alternative_id INT AUTO_INCREMENT PRIMARY KEY,
  swap_id             INT NOT NULL,
  exercise_id         INT NOT NULL,
  position_no         INT NOT NULL,
  CONSTRAINT fk_plan_swap_alternatives_swap
    FOREIGN KEY (swap_id) REFERENCES plan_swaps(swap_id) ON DELETE CASCADE,
  CONSTRAINT fk_plan_swap_alternatives_exercise
    FOREIGN KEY (exercise_id) REFERENCES exercises(exercise_id) ON DELETE RESTRICT,
  UNIQUE KEY uq_plan_swap_alternatives (swap_id, exercise_id),
  KEY ix_plan_swap_alternatives_exercise (exercise_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
