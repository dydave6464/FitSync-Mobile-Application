'use strict';
const { OAuth2Client } = require('google-auth-library');
const AppError = require('../../lib/app-error');

function create(clientId) {
  const client = new OAuth2Client(clientId);

  async function verifyIdToken(idToken) {
    let ticket;
    try {
      // Checks the signature against Google's published keys, the expiry, the
      // issuer, and that the audience is our client id. All four matter.
      ticket = await client.verifyIdToken({ idToken, audience: clientId });
    } catch (cause) {
      throw AppError.unauthorized('INVALID_GOOGLE_TOKEN', 'Google sign-in could not be verified.');
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
