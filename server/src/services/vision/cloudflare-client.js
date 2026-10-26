'use strict';
const chatClient = require('./chat-client');

// The same model Groq runs, hosted by Cloudflare Workers AI: free for about
// 10,000 "neurons" a day with no card (a photo is about 250), and Workers AI
// keeps no inputs or outputs once it has answered.
const MODEL = '@cf/qwen/qwen3.8-27b';

/// Cloudflare's OpenAI-compatible chat completions for one account. Its
/// reasoning_effort has no "none" (low is the least), so the model's
/// thinking is turned off the Qwen way instead, as Groq's 'none' does.
function create({ accountId, apiToken, ...options }) {
  return chatClient.create({
    ...options,
    provider: 'cloudflare',
    endpoint: `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountId)}/ai/v1/chat/completions`,
    apiKey: apiToken,
    model: MODEL,
    extraBody: { chat_template_kwargs: { enable_thinking: false } },
  });
}

module.exports = { create, MODEL };
