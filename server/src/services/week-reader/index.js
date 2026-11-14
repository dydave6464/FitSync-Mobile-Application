'use strict';
const stub = require('./stub');
const groqClient = require('./groq-client');

/// Picks the sentence reader, mirroring services/cues. Stub by default: no
/// test may make a network call. No production guard: without Groq the app
/// keeps its own quick reading, which is a working screen.
function createWeekReaderService(config = {}) {
  const mode = config.mode || 'stub';
  if (mode === 'stub') return stub;
  if (mode === 'groq') {
    if (!config.apiKey) throw new Error('GROQ_API_KEY is required when WEEK_READER_MODE=groq');
    return groqClient.create({ apiKey: config.apiKey, model: config.model || groqClient.DEFAULT_MODEL });
  }
  throw new Error(`Unsupported WEEK_READER_MODE: ${mode}`);
}

module.exports = { createWeekReaderService };
