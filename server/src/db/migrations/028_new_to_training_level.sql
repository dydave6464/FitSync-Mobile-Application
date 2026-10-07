-- "New to training": a gentler tier inside the manuscript's Beginner Trainee
-- ("little to no structured training experience"), for someone who has never
-- used gym equipment. The generator gives it the minimum sets and the
-- beginner session cap.
--
-- POLICY EXCEPTION, the same kind as 014: it changes a column 001 defined and
-- that is already applied on existing databases, so it cannot be an in-place
-- edit to 001. Like 014 it IS replay-safe: MODIFY COLUMN restates the whole
-- definition, so running it twice leaves the same enum.
--
-- 'new' is appended at the END. MySQL stores an enum as an index into this
-- list, and inserting in the middle would renumber every existing row.
ALTER TABLE users
  MODIFY COLUMN fitness_level ENUM('beginner','intermediate','new') NULL;
