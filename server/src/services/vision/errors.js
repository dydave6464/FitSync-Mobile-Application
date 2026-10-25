'use strict';

/// How a photo failed, for the route to answer with: VISION_BUSY (Groq's
/// rate limit, 503) or VISION_UNAVAILABLE (timeout, 5xx, an unreadable
/// reply after one retry; 502).
///
/// [status] is Groq's HTTP status when it answered (401 bad key, 404 retired
/// model, 5xx), and [cause] the original error for a timeout or a network
/// failure, so the route can log why without logging any reply body.
class VisionError extends Error {
  constructor(code, { status = null, cause } = {}) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = 'VisionError';
    this.code = code;
    this.status = status;
  }
}

module.exports = { VisionError };
