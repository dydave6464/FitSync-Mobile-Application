'use strict';
const { toPlanPayload, toRiskPayload } = require('./profile-payload');
const AppError = require('../../lib/app-error');

const REQUEST_TIMEOUT_MS = 10000;

/// The generator's refusal to build a plan with an empty day, in words the
/// user can act on. main.py names each empty day as "day N (Name)"; anything
/// else is not this refusal and stays an internal error.
function unfillableDayError(detail) {
  const days = [...String(detail).matchAll(/day \d+ \(([^)]+)\)/g)].map((m) => m[1]);
  if (days.length === 0) return null;
  const which = days.length === 1 ? `${days[0]} day` : `${days.join(' and ')} days`;
  // Full body has no other day to suggest -- "Try Full body" would be
  // telling the user to retry the very split that just came back empty.
  const suggestion = days.length === 1 && days[0] === 'Full body'
    ? 'Try adding equipment.'
    : 'Try Full body, or add equipment.';
  return new AppError(
    422,
    'UNFILLABLE_PLAN_DAY',
    `Nothing suitable for the ${which} with your injuries and equipment. ${suggestion}`,
  );
}

function create(baseUrl) {
  async function post(pathname, body) {
    let response;
    try {
      response = await fetch(new URL(pathname, baseUrl), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (err) {
      throw new Error(`ML service request to ${pathname} failed: ${err.message}`, { cause: err });
    }

    if (!response.ok) {
      if (response.status === 503 && pathname === '/generate-plan') {
        const body = await response.json().catch(() => null);
        const refusal = body && typeof body.detail === 'string'
          ? unfillableDayError(body.detail)
          : null;
        if (refusal) throw refusal;
      }
      throw new Error(`ML service ${pathname} responded ${response.status}`);
    }

    try {
      return await response.json();
    } catch (err) {
      throw new Error(
        `ML service request to ${pathname} returned an invalid response: ${err.message}`,
        { cause: err },
      );
    }
  }

  // Mapped here, at the one place a request leaves Node, so every caller --
  // onboarding, regenerate, check-in -- sends only what the service reads.
  return {
    generatePlan: (profile) => post('/generate-plan', toPlanPayload(profile)),
    estimateInjuryRisk: (payload) => post('/injury-risk', toRiskPayload(payload)),
  };
}

module.exports = { create };
