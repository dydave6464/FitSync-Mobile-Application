'use strict';
const { buildPrompt, parseReply } = require('./prompt');
const { VisionError } = require('./errors');

// What Groq and Cloudflare Workers AI share: both answer OpenAI-style chat
// completions for the same model, so one photo request serves either, and
// groq-client / cloudflare-client only say where to send it.
const TIMEOUT_MS = 15000;
// The spike's replies cost about 55-65 completion tokens per item, and two
// alternatives add about 20-28 more. The prompt caps the list at 8 items, so
// a full plate needs about 750; this leaves room for a wordier reply, since
// one cut off at the limit is retried and cut off the same way.
const MAX_TOKENS = 2000;
// Everything one photo may take, waits and retries included. The app gives
// the whole call 45 s (MealPhotoRepository.recognizeTimeout), and its clock
// also covers the upload, sign-in check and database work around this, so
// this stops at 37 s and the app still hears the answer.
const BUDGET_MS = 37000;
// No retry starts with less than this left: a photo takes 1-5 s to answer.
const MIN_ATTEMPT_MS = 5000;
// Added to a retry-after, which is in whole seconds and may be cut down
// rather than rounded ("try again in 15.2s" arrives as 15).
const RETRY_MARGIN_MS = 1000;

/// Resolves after [ms], or rejects at once if [signal] aborts first.
function wait(ms, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(new Error('aborted'));
    const timer = setTimeout(() => { signal?.removeEventListener('abort', stop); resolve(); }, ms);
    function stop() { clearTimeout(timer); reject(new Error('aborted')); }
    signal?.addEventListener('abort', stop, { once: true });
  });
}

/// The retry-after header (seconds) as milliseconds, or null when it is
/// missing or not a number.
function retryAfterMs(res) {
  const raw = res.headers?.get?.('retry-after');
  const s = raw == null || raw === '' ? NaN : Number(raw);
  return Number.isFinite(s) && s >= 0 ? Math.ceil(s * 1000) : null;
}

/// [provider] names the service in each reply (the route logs it).
/// [extraBody] is the service's own way of turning the model's thinking off.
/// [waitWhenBusy] false skips waiting out a 429, for a client whose caller
/// has somewhere else to ask. [fetchImpl], [timeoutMs], [budgetMs], [now] and
/// [sleep] are injectable for the tests. The photo goes to the service inside
/// the request body and nowhere else: nothing here logs it.
function create({
  provider, endpoint, apiKey, model, extraBody = {}, waitWhenBusy = true, fetchImpl = fetch,
  timeoutMs = TIMEOUT_MS, budgetMs = BUDGET_MS, now = Date.now, sleep = wait,
}) {
  /// One request, given at most [limitMs] and stopped if [cancel] aborts.
  /// Returns the parsed reply, or null for a reply that came back but could
  /// not be read; throws VisionError for everything else.
  async function once(body, limitMs, cancel) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), limitMs);
    try {
      const res = await fetchImpl(endpoint, {
        method: 'POST',
        signal: cancel ? AbortSignal.any([controller.signal, cancel]) : controller.signal,
        headers: { 'content-type': 'application/json', authorization: `Bearer ${apiKey}` },
        body,
      });
      // A 429 is a free plan working as documented: busy, not broken.
      // Groq's limit is per minute (input tokens for the whole app) and it
      // says how long until there is room again; Cloudflare's is a daily
      // allowance, or a moment without capacity.
      if (res.status === 429) throw new VisionError('VISION_BUSY', { status: 429, retryAfterMs: retryAfterMs(res) });
      if (res.status === 400) {
        // Groq's JSON mode answers a reply it could not make valid JSON
        // (often one cut off at max_tokens) with a 400 json_validate_failed:
        // the unreadable reply that earns one retry. Its failed_generation is
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
      if (cancel?.aborted) throw new VisionError('VISION_CANCELLED');
      // Timeout, abort, DNS, a malformed envelope: one answer for all.
      throw new VisionError('VISION_UNAVAILABLE', { cause: err });
    } finally {
      clearTimeout(timer);
    }
  }

  /// [signal] aborts when the caller stops waiting (the app left): no new
  /// request starts after that, and one in flight is dropped. [deadline]
  /// (a now() time) is a budget shared with another client; without one,
  /// this photo gets [budgetMs] of its own.
  async function recognize({ imageBase64, mimeType, menuNames, signal, deadline }) {
    const body = JSON.stringify({
      model,
      temperature: 0.2,
      max_tokens: MAX_TOKENS,
      ...extraBody,
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
    // a 429 is waited out when the service says how long, and an unreadable
    // reply is asked again. A timeout or a 5xx is not retried -- the user
    // would only wait another 15 s for the same answer.
    const end = deadline ?? now() + budgetMs;
    const left = () => end - now();
    let waited = false;
    let retried = false;
    for (;;) {
      if (signal?.aborted) throw new VisionError('VISION_CANCELLED');
      let reply;
      try {
        reply = await once(body, Math.max(1, Math.min(timeoutMs, left())), signal);
      } catch (err) {
        const pause = err.retryAfterMs == null ? null : err.retryAfterMs + RETRY_MARGIN_MS;
        if (err.code !== 'VISION_BUSY' || !waitWhenBusy || waited || pause == null || left() - pause < MIN_ATTEMPT_MS) throw err;
        waited = true;
        try {
          await sleep(pause, signal);
        } catch {
          throw new VisionError('VISION_CANCELLED');
        }
        continue;
      }
      if (reply) return { ...reply, provider };
      if (retried || left() < MIN_ATTEMPT_MS) throw new VisionError('VISION_UNAVAILABLE');
      retried = true;
    }
  }

  return { recognize, model };
}

module.exports = { create, wait, BUDGET_MS, MIN_ATTEMPT_MS, RETRY_MARGIN_MS };
