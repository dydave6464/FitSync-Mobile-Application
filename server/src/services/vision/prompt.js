'use strict';
const { menuLine, MAX_CARDS } = require('../../lib/photo-match');

/// Dishes the model mixes up, and what tells them apart. Written from the
/// dishes themselves and the real check's misses (sinigang -> tinola,
/// kare-kare -> bulalo, skinless longganisa -> hotdog) before the 42-photo
/// test set was run. Each group is shown by exact menu name, so the model
/// can copy the right one; a test checks every name is a FitSync food.
const LOOK_ALIKES = [
  {
    names: ['Sinigang na baboy', 'Sinigang na hipon', 'Sinigang na bangus (milkfish sour soup)', 'Tinolang manok', 'Nilagang baka', 'Nilagang baboy (boiled pork soup)', 'Bulalo'],
    tell: 'sinigang: SOUR, cloudy or reddish broth with kangkong, radish, okra or long green chili; tinola: clear GINGER broth, chicken, green papaya or sayote, malunggay or chili leaves; nilaga: clear broth, beef or pork chunks, potato, cabbage or pechay; bulalo: beef shank with a round marrow bone, corn on the cob, pechay.',
  },
  {
    names: ['Kare-kare', 'Chicken afritada', 'Pork menudo', 'Beef caldereta', 'Chicken adobo', 'Pork adobo', 'Dinuguan (pork blood stew)'],
    tell: 'kare-kare: thick ORANGE peanut sauce, oxtail or crispy pork, eggplant, string beans, pechay, bagoong; afritada: chicken, light tomato sauce, potato, carrot, bell pepper; menudo: small diced pork, tomato sauce, diced potato and carrot, peas or raisins; caldereta: beef, thick dark tomato sauce, often cheese or olives; adobo: dark brown soy-vinegar sauce, no tomato, bay leaf, garlic; dinuguan: near-black blood stew.',
  },
  {
    names: ['Vigan longganisa', 'Lucban longganisa', 'Longganisa hamonado (sweet)', 'Red Filipino hotdog', 'Pork tocino', 'Beef tapa'],
    tell: 'longganisa: short, uneven, often skinless links, orange-red to brown; hotdog: smooth, bright red, even cylinder; tocino: glossy red-pink sweet pork slices; tapa: thin dark brown dried beef.',
  },
  {
    names: ['Lumpiang shanghai', 'Turon', 'Kikiam (Filipino fried roll)'],
    tell: 'shanghai: thin small meat rolls, often cut; turon: thicker banana roll with caramelised sugar; kikiam: brown uneven roll, sliced, with fishballs.',
  },
  {
    names: ['Pancit canton', 'Pancit bihon', 'Mang Inasal Palabok', 'Spaghetti with meat sauce'],
    tell: 'canton: thick yellow egg noodles; bihon: thin rice noodles, white or soy-brown; palabok: thin noodles under orange sauce with crushed chicharon, shrimp, egg; spaghetti: sweet red sauce, hotdog slices, cheese.',
  },
  {
    names: ['Lechon manok', 'Chicken inasal', 'Kwek-kwek with vinegar dip', 'Tokneneng (battered fried chicken egg)', 'Fishball with sweet sauce (street food)'],
    tell: 'lechon manok: whole or half roast chicken, glossy brown skin; inasal: grilled pieces, orange-yellow annatto, char marks; kwek-kwek: small orange battered quail eggs; tokneneng: bigger orange battered chicken eggs; fishball: flat, round, grey-brown.',
  },
];

/// The 2026-10-21 spike's second prompt -- FitSync's food names as a menu,
/// which took the test photos from 4 of 10 dishes right to 8 of 10 -- plus
/// one rule asking for up to two other menu names per item, for the confirm
/// screen's "Not right?" chips, and the look-alike hints before the reply
/// format (the menu stays last). Each menu name is one line of its own
/// (saved FatSecret copies are third-party text); matchItems compares names
/// the same way, so the AI's copy of a cleaned name still matches.
function buildPrompt(menuNames) {
  return `You recognise food for a Philippine fitness app. Look at the meal photo and list EVERY distinct food or drink item that one person is eating.

Rules:
- For each item, pick the closest name from the MENU below and copy it exactly into "menu". If nothing on the menu fits, set "menu" to null and give your best name.
- If the whole plate matches one combo on the menu (for example "Tapsilog" or "Longsilog"), you may list that combo once instead of its parts.
- A soup or stew is ONE item: do not also list its ingredients or broth separately.
- Do not list the same item twice; use quantity instead.
- Estimate each portion as quantity + household unit (cup, piece, slice, bowl, tbsp, glass, skewer) for one person, plus grams. Confidence 0 to 1.
- For each item, also list in "alternatives" up to 2 other MENU names it could be (exact menu names, most likely first), or [] if none fit.
- List at most ${MAX_CARDS} items (the most important ones if there are more).

LOOK-ALIKES (check these before you choose):
${LOOK_ALIKES.map((g) => `- ${g.names.join(' / ')}: ${g.tell}`).join('\n')}

Reply with JSON only: {"items":[{"menu":"<exact menu name or null>","name":"","quantity":0,"unit":"","grams":0,"confidence":0,"alternatives":[]}]}

MENU:
${menuNames.map(menuLine).join('\n')}`;
}

const text = (v) => (typeof v === 'string' && v.trim() !== '' ? v.trim() : null);
const amount = (v) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null);

/// The model's reply, checked. The reply is untrusted text: anything that
/// isn't JSON with an `items` array is null (the caller asks once more).
/// Inside it, a field of the wrong kind becomes null and an item with no
/// name at all is skipped, rather than failing the whole photo.
function parseReply(raw) {
  if (typeof raw !== 'string' || raw.trim() === '') return null;
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || !Array.isArray(parsed.items)) return null;
  const items = [];
  for (const it of parsed.items) {
    if (!it || typeof it !== 'object') continue;
    const menu = text(it.menu);
    const name = text(it.name) ?? menu;
    if (!name) continue;
    const confidence = amount(it.confidence);
    items.push({
      menu,
      name: name.slice(0, 255),
      quantity: amount(it.quantity),
      unit: text(it.unit),
      grams: amount(it.grams),
      confidence: confidence == null ? null : Math.min(1, confidence),
      alternatives: Array.isArray(it.alternatives) ? it.alternatives.map(text).filter(Boolean) : [],
    });
  }
  return { items };
}

module.exports = { buildPrompt, parseReply, LOOK_ALIKES };
