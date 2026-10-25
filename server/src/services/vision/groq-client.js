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
// The spike's replies cost about 55-65 completion tokens per item, and two
// alternatives add about 20-28 more. The prompt caps the list at 8 items, so
// a full plate needs about 750; this leaves room for a wordier reply, since
// one cut off at the limit is retried and cut off the same way.
const MAX_TOKENS = 2000;
// Everything one photo may take, waits and retries included: under the app's
// own 45 s, so the app hears the answer rather than giving up first.
const BUDGET_MS = 40000;
// No retry starts with less than this left: a photo takes 1-5 s to answer.
const MIN_ATTEMPT_MS = 5000;
// Added to Groq's retry-after, which is rounded to whole seconds.
const RETRY_MARGIN_MS = 500;

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/// Groq's retry-after header (seconds) as milliseconds, or null when it is
/// missing or not a number.
function retryAfterMs(res) {
  const raw = res.headers?.get?.('retry-after');
  const s = raw == null || raw === '' ? NaN : Number(raw);
  return Number.isFinite(s) && s >= 0 ? Math.ceil(s * 1000) : null;
}

/// [fetchImpl], [timeoutMs], [budgetMs], [now] and [sleep] are injectable for
/// the tests. The photo goes to Groq inside the request body and nowhere
/// else: nothing here logs it.
function create({
  apiKey, model = DEFAULT_MODEL, fetchImpl = fetch, timeoutMs = TIMEOUT_MS,
  budgetMs = BUDGET_MS, now = Date.now, sleep = wait,
}) {
  /// One request, given at most [limitMs]. Returns the parsed reply, or null
  /// for a reply that came back but could not be read; throws VisionError
  /// for everything else.
  async function once(body, limitMs) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), limitMs);
    try {
      const res = await fetchImpl(ENDPOINT, {
        method: 'POST',
        signal: controller.signal,
        headers: { 'content-type': 'application/json', authorization: `Bearer ${apiKey}` },
        body,
      });
      // A 429 is the free plan working as documented: busy, not broken. Its
      // limit is per minute (input tokens for the whole app), and Groq says
      // how long until there is room again.
      if (res.status === 429) throw new VisionError('VISION_BUSY', { status: 429, retryAfterMs: retryAfterMs(res) });
      if (res.status === 400) {
        // JSON mode answers a reply it could not make valid JSON (often one
        // cut off at max_tokens) with a 400 json_validate_failed: the
        // unreadable reply that earns one retry. Its failed_generation is
        // never logged or kept.
        const err = await res.json().catch(() => null);
        if (err?.error?.code === 'json_validate_failed') return null;
      }
      if (!res.ok) throw new VisionError('VISION_UNAVAILABLE', { status: res.status });
      const json = await res.json();
      const choice = json?.choices?.[0];
      // Cut off at the token limit: a list that may be missing items.
      if (choice?.finish_reason === 'length') return null;
      return parseReply(choice?.message?.content);
    } catch (err) {
      if (err instanceof VisionError) throw err;
      // Timeout, abort, DNS, a malformed envelope: one answer for all.
      throw new VisionError('VISION_UNAVAILABLE', { cause: err });
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
    // Two second chances, each at most once and only while the budget allows:
    // a 429 is waited out when Groq says how long, and an unreadable reply is
    // asked again. A timeout or a 5xx is not retried -- the user would only
    // wait another 15 s for the same answer.
    const deadline = now() + budgetMs;
    const left = () => deadline - now();
    let waited = false;
    let retried = false;
    for (;;) {
      let reply;
      try {
        reply = await once(body, Math.max(1, Math.min(timeoutMs, left())));
      } catch (err) {
        const pause = err.retryAfterMs == null ? null : err.retryAfterMs + RETRY_MARGIN_MS;
        if (err.code !== 'VISION_BUSY' || waited || pause == null || left() - pause < MIN_ATTEMPT_MS) throw err;
        waited = true;
        await sleep(pause);
        continue;
      }
      if (reply) return reply;
      if (retried || left() < MIN_ATTEMPT_MS) throw new VisionError('VISION_UNAVAILABLE');
      retried = true;
    }
  }

  return { recognize, model };
}

module.exports = { create, DEFAULT_MODEL };
