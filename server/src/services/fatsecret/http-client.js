'use strict';

const TOKEN_URL = 'https://oauth.fatsecret.com/connect/token';
const API_URL = 'https://platform.fatsecret.com/rest/server.api';
// Per request. The search route also caps the whole call (routes/foods.js).
const REQUEST_TIMEOUT_MS = 3000;
const TOKEN_MARGIN_MS = 60_000;
const MAX_RESULTS = 20;
// FatSecret's "invalid id" error. Every other error code is a real failure.
const INVALID_ID = 106;
// Sanity bounds: foods.calories is INT, the macro columns DECIMAL(5,2).
const MAX_KCAL = 5000;
const MAX_GRAMS = 999.99;

const DESCRIPTION = /^Per (.+?) - Calories: ([\d.]+)kcal \| Fat: ([\d.]+)g \| Carbs: ([\d.]+)g \| Protein: ([\d.]+)g/;

const round2 = (n) => Math.round(n * 100) / 100;

/// "Per 1 cup - Calories: 466kcal | Fat: 30.71g | Carbs: 5.46g | Protein: 40.60g"
/// -> its serving and numbers, or null. Exported for its own tests.
function parseDescription(text) {
  const m = DESCRIPTION.exec(String(text || ''));
  if (!m) return null;
  return {
    servingDesc: m[1],
    kcal: Math.round(Number(m[2])),
    fatG: round2(Number(m[3])),
    carbsG: round2(Number(m[4])),
    proteinG: round2(Number(m[5])),
  };
}

function plausible(f) {
  return f.kcal >= 0 && f.kcal <= MAX_KCAL
    && [f.proteinG, f.carbsG, f.fatG].every((g) => Number.isFinite(g) && g >= 0 && g <= MAX_GRAMS);
}

function displayName(item) {
  return item.brand_name ? `${item.food_name} (${item.brand_name})` : item.food_name;
}

function asArray(x) {
  if (x == null) return [];
  return Array.isArray(x) ? x : [x];
}

/// [fetchImpl] and [now] are injectable so tests never reach the network.
function create({ clientId, clientSecret, fetchImpl = fetch, now = Date.now }) {
  let token = null;
  let expiresAt = 0;

  async function accessToken() {
    if (token && now() < expiresAt - TOKEN_MARGIN_MS) return token;
    const res = await fetchImpl(TOKEN_URL, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString('base64')}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'grant_type=client_credentials&scope=basic',
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`FatSecret token request failed: ${res.status}`);
    const body = await res.json();
    token = body.access_token;
    expiresAt = now() + Number(body.expires_in) * 1000;
    return token;
  }

  async function call(params) {
    const bearer = await accessToken();
    const url = `${API_URL}?${new URLSearchParams({ ...params, format: 'json' })}`;
    const res = await fetchImpl(url, {
      headers: { Authorization: `Bearer ${bearer}` },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`FatSecret ${params.method} failed: ${res.status}`);
    return res.json();
  }

  function fail(method, error) {
    // Code 21 is "Invalid IP address": the server's IP is not allow-listed
    // in the FatSecret developer console.
    return new Error(`FatSecret ${method} error ${error.code}: ${error.message}`);
  }

  return {
    async search(q) {
      const body = await call({ method: 'foods.search', search_expression: q, max_results: String(MAX_RESULTS) });
      if (body.error) throw fail('foods.search', body.error);
      return asArray(body.foods && body.foods.food)
        .map((item) => {
          const parsed = parseDescription(item.food_description);
          return parsed && { externalId: String(item.food_id), name: displayName(item), ...parsed };
        })
        .filter((f) => f && plausible(f))
        .map(({ externalId, name, servingDesc, kcal, proteinG, carbsG, fatG }) => ({
          externalId, name, servingDesc, kcal, proteinG, carbsG, fatG,
        }));
    },

    async get(externalId) {
      const body = await call({ method: 'food.get.v2', food_id: String(externalId) });
      if (body.error) {
        if (Number(body.error.code) === INVALID_ID) return null;
        throw fail('food.get.v2', body.error);
      }
      const item = body.food;
      const servings = asArray(item && item.servings && item.servings.serving);
      const s = servings.find((x) => String(x.is_default) === '1') || servings[0];
      if (!s) return null;
      const food = {
        externalId: String(item.food_id),
        name: displayName(item),
        servingDesc: s.serving_description || null,
        kcal: Math.round(Number(s.calories)),
        proteinG: round2(Number(s.protein)),
        carbsG: round2(Number(s.carbohydrate)),
        fatG: round2(Number(s.fat)),
      };
      return plausible(food) ? food : null;
    },
  };
}

module.exports = { create, parseDescription };
