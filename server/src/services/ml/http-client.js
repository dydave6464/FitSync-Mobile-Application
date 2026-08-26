'use strict';

function create(baseUrl) {
  async function post(pathname, body) {
    const response = await fetch(new URL(pathname, baseUrl), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      throw new Error(`ML service ${pathname} responded ${response.status}`);
    }
    return response.json();
  }

  return {
    generatePlan: (profile) => post('/generate-plan', profile),
    estimateInjuryRisk: (payload) => post('/injury-risk', payload),
  };
}

module.exports = { create };
