'use strict';
const AppError = require('../../lib/app-error');

// Fixed identities so tests can assert exact values. The unverified one exists
// specifically to exercise the account-linking refusal.
const IDENTITIES = {
  'stub-token-juan': {
    subject: 'stub-sub-juan',
    email: 'juan@example.com',
    emailVerified: true,
    fullName: 'Juan Dela Cruz',
  },
  'stub-token-maria': {
    subject: 'stub-sub-maria',
    email: 'maria@example.com',
    emailVerified: true,
    fullName: 'Maria Santos',
  },
  'stub-token-unverified': {
    subject: 'stub-sub-unverified',
    email: 'unverified@example.com',
    emailVerified: false,
    fullName: 'Unverified Person',
  },
};

async function verifyIdToken(idToken) {
  const identity = IDENTITIES[idToken];
  if (!identity) {
    throw AppError.unauthorized('INVALID_GOOGLE_TOKEN', 'Google sign-in could not be verified.');
  }
  return { ...identity };
}

module.exports = { verifyIdToken, IDENTITIES };
