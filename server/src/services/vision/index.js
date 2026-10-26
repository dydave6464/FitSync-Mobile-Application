'use strict';
const stub = require('./stub');
const groqClient = require('./groq-client');
const cloudflareClient = require('./cloudflare-client');
const fallback = require('./fallback');

/// Picks the photo recogniser, like services/cues. The stub is the default
/// so no test makes a network call. groq: Groq, with Cloudflare Workers AI
/// (the same model) as the automatic backup when both Cloudflare settings
/// are given. cloudflare: Cloudflare alone, the switch for the day Groq
/// retires its Preview model. [deps] (fetchImpl, now, sleep) are for the
/// tests.
function createVisionService(visionConfig = {}, deps = {}) {
  const mode = visionConfig.mode || 'stub';
  const { accountId, apiToken } = visionConfig.cloudflare || {};

  if (mode === 'stub') return stub;

  if (mode === 'cloudflare') {
    if (!accountId || !apiToken) {
      throw new Error('CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN are required when VISION_MODE=cloudflare');
    }
    return cloudflareClient.create({ accountId, apiToken, ...deps });
  }

  if (mode === 'groq') {
    // Fail at startup rather than on the first photo.
    if (!visionConfig.apiKey) {
      throw new Error('GROQ_API_KEY is required when VISION_MODE=groq');
    }
    // Half a setting is a typo, not a choice: a backup silently left off
    // would only show when Groq is busy.
    if (Boolean(accountId) !== Boolean(apiToken)) {
      throw new Error('Set both CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN, or neither');
    }
    const groq = (waitWhenBusy) => groqClient.create({
      apiKey: visionConfig.apiKey,
      model: visionConfig.model || groqClient.DEFAULT_MODEL,
      waitWhenBusy,
      ...deps,
    });
    if (!accountId) return groq(true);
    return fallback.create({
      primary: groq(false),
      backup: cloudflareClient.create({ accountId, apiToken, waitWhenBusy: false, ...deps }),
      now: deps.now,
      sleep: deps.sleep,
    });
  }

  throw new Error(`Unsupported VISION_MODE: ${mode}`);
}

module.exports = { createVisionService };
