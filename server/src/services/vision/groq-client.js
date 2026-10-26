'use strict';
const chatClient = require('./chat-client');

const ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';
// Free with no card, keeps no data by default, and in the 2026-10-21 spike
// named 8 of 10 Filipino plates right given the menu, in 1.3-1.9 s. Groq
// lists it as a Preview model ("may be discontinued at short notice"), so
// VISION_MODEL overrides it.
const DEFAULT_MODEL = 'qwen/qwen3.8-27b';

/// Groq's chat completions; everything else is chat-client's. The rest of
/// the options (waitWhenBusy, and the test hooks) pass straight through.
function create({ apiKey, model = DEFAULT_MODEL, ...options }) {
  return chatClient.create({
    ...options,
    provider: 'groq',
    endpoint: ENDPOINT,
    apiKey,
    model,
    extraBody: { reasoning_effort: 'none' },
  });
}

module.exports = { create, DEFAULT_MODEL };
