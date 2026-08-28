'use strict';
const { OAuth2Client } = require('google-auth-library');
const AppError = require('../../lib/app-error');

// Detect infrastructure/transport-level failures so they report as 500 (service broken)
// rather than 401 (bad token). Real token failures stay as 401.
function isTransportFailure(err) {
  // Node.js system errors: DNS, connection, timeout
  if (err.code && ['ENOTFOUND', 'ECONNREFUSED', 'ETIMEDOUT', 'EAI_AGAIN'].includes(err.code)) {
    return true;
  }
  // Abort/timeout errors from fetch
  if (err.name === 'AbortError' || err.name === 'TimeoutError') {
    return true;
  }
  return false;
}

function create(clientId) {
  const client = new OAuth2Client(clientId);

  async function verifyIdToken(idToken) {
    let ticket;
    try {
      // Checks the signature against Google's published keys, the expiry, the
      // issuer, and that the audience is our client id. All four matter.
      ticket = await client.verifyIdToken({ idToken, audience: clientId });
    } catch (cause) {
      // Transport/infrastructure failures (DNS, connection refused, timeout, abort)
      // are not auth failures. They mean we could not check the token.
      if (isTransportFailure(cause)) {
        throw new Error(
          `Could not verify Google sign-in: ${cause.message}`,
          { cause },
        );
      }
      // Real token failures (bad signature, expired, wrong audience, malformed)
      const err = AppError.unauthorized('INVALID_GOOGLE_TOKEN', 'Google sign-in could not be verified.');
      err.cause = cause;
      throw err;
    }
    const payload = ticket.getPayload();
    if (!payload || !payload.sub) {
      throw AppError.unauthorized('INVALID_GOOGLE_TOKEN', 'Google sign-in could not be verified.');
    }
    return {
      subject: payload.sub,
      email: payload.email || null,
      emailVerified: payload.email_verified === true,
      fullName: payload.name || null,
    };
  }

  return { verifyIdToken };
}

module.exports = { create };
