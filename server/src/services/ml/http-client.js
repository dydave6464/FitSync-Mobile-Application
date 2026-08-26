'use strict';

const REQUEST_TIMEOUT_MS = 10000;

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

  return {
    generatePlan: (profile) => post('/generate-plan', profile),
    estimateInjuryRisk: (payload) => post('/injury-risk', payload),
  };
}

module.exports = { create };
