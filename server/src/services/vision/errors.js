'use strict';

/// How a photo failed, for the route to answer with: VISION_BUSY (the
/// service's rate limit, 503) or VISION_UNAVAILABLE (timeout, 5xx, an unreadable
/// reply after one retry; 502). VISION_CANCELLED: the caller's signal was
/// aborted (the app left), so nothing more was sent and nobody is waiting
/// for an answer.
///
/// [status] is the service's HTTP status when it answered (401 bad key, 404
/// retired model, 5xx), and [cause] the original error for a timeout or a network
/// failure, so the route can log why without logging any reply body.
/// [retryAfterMs] is how long the service said to wait before asking again
/// (its retry-after header on a 429), or null when it did not say. When the
/// Cloudflare backup was asked too and failed, services/vision/fallback sets
/// `backup` to its VisionError.
class VisionError extends Error {
  constructor(code, { status = null, cause, retryAfterMs = null } = {}) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = 'VisionError';
    this.code = code;
    this.status = status;
    this.retryAfterMs = retryAfterMs;
  }
}

module.exports = { VisionError };
