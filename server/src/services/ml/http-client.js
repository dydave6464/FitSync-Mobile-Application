'use strict';
const { toPlanPayload, toRiskPayload } = require('./profile-payload');
const AppError = require('../../lib/app-error');

const REQUEST_TIMEOUT_MS = 10000;

/// The dish classifier answers in well under a second. The photo route asks
/// it beside the vision AI and must never wait on it longer than this.
const DISH_TIMEOUT_MS = 2000;

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
  // main.py adds this clause when only beginner-friendly exercises were
  // considered (fitness level or health check). Then the rule may be the
  // reason, not the injuries, and blaming them would send the user after
  // the wrong fix.
  const message = /Only exercises marked beginner-friendly were considered/.test(String(detail))
    ? `Nothing beginner-friendly for the ${which} with your equipment yet. ${suggestion}`
    : `Nothing suitable for the ${which} with your injuries and equipment. ${suggestion}`;
  return new AppError(422, 'UNFILLABLE_PLAN_DAY', message);
}

function create(baseUrl) {
  async function post(pathname, body, { timeoutMs = REQUEST_TIMEOUT_MS, signal = null } = {}) {
    const timeout = AbortSignal.timeout(timeoutMs);
    let response;
    try {
      response = await fetch(new URL(pathname, baseUrl), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
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
    // The generator screen's Auto length (spec 2026-11-14): the same profile
    // payload as generate-plan, so ML reads the fields it would build from.
    planParameters: (profile) => post('/plan-parameters', toPlanPayload(profile)),
    estimateInjuryRisk: (payload) => post('/injury-risk', toRiskPayload(payload)),
    // The dish classifier's second opinion on a meal photo (spec
    // 2026-11-05-food-classifier). [signal] is the photo request's own:
    // when the app stops waiting, this stops too.
    classifyDish: ({ imageBase64, mimeType, signal }) => post(
      '/classify-dish', { image: imageBase64, mimeType }, { timeoutMs: DISH_TIMEOUT_MS, signal },
    ),
  };
}

module.exports = { create, DISH_TIMEOUT_MS };
