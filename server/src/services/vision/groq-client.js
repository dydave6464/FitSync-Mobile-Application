'use strict';
const { buildPrompt, parseReply } = require('./prompt');
const { VisionError } = require('./errors');

const ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';
// Free with no card, keeps no data by default, and in the 2026-10-21 spike
// named 8 of 10 Filipino plates right given the menu, in 1.3-1.9 s. Groq
// lists it as a Preview model ("may be discontinued at short notice"), so
// VISION_MODEL overrides it.
const DEFAULT_MODEL = 'qwen/qwen3.8-27b';
const TIMEOUT_MS = 15000;
// The spike's replies used ~170 completion tokens for two items; eight items
// with two alternatives each stay well inside this.
const MAX_TOKENS = 900;

/// [fetchImpl] and [timeoutMs] are injectable for the tests. The photo goes
/// to Groq inside the request body and nowhere else: nothing here logs it.
function create({ apiKey, model = DEFAULT_MODEL, fetchImpl = fetch, timeoutMs = TIMEOUT_MS }) {
  /// One request. Returns the parsed reply, or null for a reply that came
  /// back but could not be read; throws VisionError for everything else.
  async function once(body) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(ENDPOINT, {
        method: 'POST',
        signal: controller.signal,
        headers: { 'content-type': 'application/json', authorization: `Bearer ${apiKey}` },
        body,
      });
      // A 429 is the free plan working as documented: busy, not broken.
      if (res.status === 429) throw new VisionError('VISION_BUSY');
      if (!res.ok) throw new VisionError('VISION_UNAVAILABLE');
      const json = await res.json();
      const choice = json?.choices?.[0];
      // Cut off at the token limit: a list that may be missing items.
      if (choice?.finish_reason === 'length') return null;
      return parseReply(choice?.message?.content);
    } catch (err) {
      if (err instanceof VisionError) throw err;
      // Timeout, abort, DNS, a malformed envelope: one answer for all.
      throw new VisionError('VISION_UNAVAILABLE');
    } finally {
      clearTimeout(timer);
    }
  }

  async function recognize({ imageBase64, mimeType, menuNames }) {
    const body = JSON.stringify({
      model,
      temperature: 0.2,
      max_tokens: MAX_TOKENS,
      reasoning_effort: 'none',
      response_format: { type: 'json_object' },
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: buildPrompt(menuNames) },
          { type: 'image_url', image_url: { url: `data:${mimeType};base64,${imageBase64}` } },
        ],
      }],
    });
    // One retry, only for a reply that arrived unreadable: a timeout or a
    // 5xx would just make the user wait another 15 seconds for the same.
    const first = await once(body);
    if (first) return first;
    const second = await once(body);
    if (second) return second;
    throw new VisionError('VISION_UNAVAILABLE');
  }

  return { recognize, model };
}

module.exports = { create, DEFAULT_MODEL };
