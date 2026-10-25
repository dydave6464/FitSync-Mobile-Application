'use strict';

/// How a photo failed, for the route to answer with: VISION_BUSY (Groq's
/// rate limit, 503) or VISION_UNAVAILABLE (timeout, 5xx, an unreadable
/// reply after one retry; 502).
class VisionError extends Error {
  constructor(code) {
    super(code);
    this.name = 'VisionError';
    this.code = code;
  }
}

module.exports = { VisionError };
