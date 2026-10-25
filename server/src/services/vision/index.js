'use strict';
const stub = require('./stub');
const groqClient = require('./groq-client');

/// Picks the photo recogniser, like services/cues. The stub is the default
/// so no test makes a network call. A Cloudflare Workers AI driver (same
/// model) would be one more mode here if Groq retires the Preview model.
function createVisionService(visionConfig = {}) {
  const mode = visionConfig.mode || 'stub';

  if (mode === 'stub') return stub;

  if (mode === 'groq') {
    // Fail at startup rather than on the first photo.
    if (!visionConfig.apiKey) {
      throw new Error('GROQ_API_KEY is required when VISION_MODE=groq');
    }
    return groqClient.create({
      apiKey: visionConfig.apiKey,
      model: visionConfig.model || groqClient.DEFAULT_MODEL,
    });
  }

  throw new Error(`Unsupported VISION_MODE: ${mode}`);
}

module.exports = { createVisionService };
