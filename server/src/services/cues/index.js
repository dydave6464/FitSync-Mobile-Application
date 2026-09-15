'use strict';
const stub = require('./stub');
const groqClient = require('./groq-client');

/// Picks the cue generator, mirroring `services/ml`.
///
/// Defaults to the stub for the same reason ML_MODE does: no test in this
/// repository may make a network call. Unlike GOOGLE_MODE and MAIL_MODE there
/// is deliberately NO production guard -- stub cues in production degrade one
/// screen to the catalogue's own text, which is a working product, not a
/// locked-out one.
function createCueService(cuesConfig = {}) {
  const mode = cuesConfig.mode || 'stub';

  if (mode === 'stub') return stub;

  if (mode === 'groq') {
    // Fail here rather than on the first workout of the day.
    if (!cuesConfig.apiKey) {
      throw new Error('GROQ_API_KEY is required when CUES_MODE=groq');
    }
    return groqClient.create({
      apiKey: cuesConfig.apiKey,
      model: cuesConfig.model || groqClient.DEFAULT_MODEL,
    });
  }

  throw new Error(`Unsupported CUES_MODE: ${mode}`);
}

module.exports = { createCueService };
