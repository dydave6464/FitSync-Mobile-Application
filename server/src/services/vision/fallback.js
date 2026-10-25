'use strict';
const { wait, BUDGET_MS, MIN_ATTEMPT_MS, RETRY_MARGIN_MS } = require('./chat-client');
const { VisionError } = require('./errors');

/// Groq first, and the same model on Cloudflare when Groq can't answer --
/// busy (its free plan's per-minute limit), down, or unreadable -- so a
/// photo sent within ~40 s of another is answered in seconds instead of
/// waiting out Groq's retry-after. Only when Cloudflare can't answer either
/// does it do what Groq alone would: wait out Groq's busy reply once, if it
/// said how long and the wait fits. Both share one budget.
///
/// [primary] and [backup] are chat clients made with waitWhenBusy false: the
/// waiting is decided here. A failure is [primary]'s error, carrying
/// [backup]'s as `backup` for the route's log line.
function create({ primary, backup, budgetMs = BUDGET_MS, now = Date.now, sleep = wait }) {
  async function recognize(args) {
    const deadline = now() + budgetMs;
    const left = () => deadline - now();
    const ask = (client) => client.recognize({ ...args, deadline });

    let failure;
    let failedAt;
    try {
      return await ask(primary);
    } catch (err) {
      if (err.code === 'VISION_CANCELLED') throw err;
      failure = err;
      failedAt = now();
    }
    if (left() < MIN_ATTEMPT_MS) throw failure;
    try {
      return await ask(backup);
    } catch (err) {
      if (err.code === 'VISION_CANCELLED') throw err;
      failure.backup = err;
    }

    // Groq's retry-after counted from its reply, so the time Cloudflare took
    // comes off the wait.
    if (failure.code !== 'VISION_BUSY' || failure.retryAfterMs == null) throw failure;
    const pause = Math.max(0, failure.retryAfterMs + RETRY_MARGIN_MS - (now() - failedAt));
    if (left() - pause < MIN_ATTEMPT_MS) throw failure;
    if (pause > 0) {
      try {
        await sleep(pause, args.signal);
      } catch {
        throw new VisionError('VISION_CANCELLED');
      }
    }
    try {
      return await ask(primary);
    } catch (err) {
      if (err.code !== 'VISION_CANCELLED') err.backup = failure.backup;
      throw err;
    }
  }

  return { recognize, model: primary.model };
}

module.exports = { create };
