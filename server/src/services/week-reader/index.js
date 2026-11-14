'use strict';
const stub = require('./stub');
const groqClient = require('./groq-client');

/// Picks the sentence reader, mirroring services/cues. Stub by default: no
/// test may make a network call. The stub's fixed phrases are not a reading
/// of anyone's week, so a running server never uses it: server.js swaps in
/// offWeekReader instead (see below).
///
/// [logger] (the server's) is where the Groq client says why a reading
/// failed; left out, it says nothing.
function createWeekReaderService(config = {}, logger = undefined) {
  const mode = config.mode || 'stub';
  if (mode === 'stub') return stub;
  if (mode === 'groq') {
    if (!config.apiKey) throw new Error('GROQ_API_KEY is required when WEEK_READER_MODE=groq');
    return groqClient.create({
      apiKey: config.apiKey,
      model: config.model || groqClient.DEFAULT_MODEL,
      logger,
    });
  }
  throw new Error(`Unsupported WEEK_READER_MODE: ${mode}`);
}

/// What a running server outside tests uses when WEEK_READER_MODE is not
/// groq. Every reading fails, so the route answers 503 AI_BUSY and the app
/// silently keeps its own quick reading. The stub would instead answer 200
/// with a near-empty reading tagged "Read by AI" that replaces the phone's
/// correct lines.
const offWeekReader = { read: async () => null, model: 'off' };

module.exports = { createWeekReaderService, offWeekReader };
