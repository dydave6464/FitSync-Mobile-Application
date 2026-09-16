'use strict';
const { flagFor } = require('./cue-gate');
const { readPair, writePair, catalogueCues } = require('./ai-cues');

// One in-flight generation per pair, process-wide. Two screens opening the same
// exercise at once would otherwise both call, and a burst is precisely what a
// free-tier rate limit refuses. Entries are removed as they settle, so this
// never grows: it holds only what is being generated right now.
const inFlight = new Map();

function once(key, work) {
  const running = inFlight.get(key);
  if (running) return running;

  const started = work().finally(() => inFlight.delete(key));
  inFlight.set(key, started);
  return started;
}

/// The cues to show for one exercise, for one user.
///
/// Four outcomes, and only one of them costs anything:
///
///   not flagged        -> the catalogue's own cues, no service call
///   flagged, cached    -> the stored pair, no service call
///   flagged, a miss    -> generate once, store, return it
///   flagged, generation failed -> the catalogue's cues, nothing stored
///
/// Never throws for a generation failure, and never leaves the caller waiting
/// on anything but the database once a pair is cached. A workout is never
/// blocked by Groq: a timeout, a 429 or a malformed reply all land in the last
/// row above, which is a working screen.
async function resolveCues(pool, service, userId, exerciseId) {
  const fallback = async () => ({
    source: 'catalogue',
    injury: null,
    cues: await catalogueCues(pool, exerciseId),
  });

  const flag = await flagFor(pool, userId, exerciseId);
  if (!flag) return fallback();

  const injury = {
    injuryId: flag.injuryId,
    name: flag.injuryName,
    reason: flag.reason,
  };

  const cached = await readPair(pool, exerciseId, flag.injuryId);
  if (cached.length > 0) return { source: 'ai', injury, cues: cached };

  const [rows] = await pool.query(
    'SELECT name, muscle_group FROM exercises WHERE exercise_id = ?',
    [exerciseId],
  );
  // flagFor joined this row already, so an empty result means it vanished
  // between the two queries. Not worth a generation.
  if (rows.length === 0) return fallback();

  const generated = await once(`${exerciseId}:${flag.injuryId}`, async () => {
    const cues = await service.generate({
      exerciseName: rows[0].name,
      muscleGroup: rows[0].muscle_group,
      injuryName: flag.injuryName,
      reason: flag.reason,
    });
    // The service returns null for every failure it has; it does not throw.
    if (!cues || cues.length === 0) return null;
    await writePair(pool, exerciseId, flag.injuryId, cues, service.model);
    return cues;
  });

  if (!generated) return fallback();
  return { source: 'ai', injury, cues: generated };
}

module.exports = { resolveCues };
