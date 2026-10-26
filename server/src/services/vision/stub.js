'use strict';

// Deterministic and offline, for tests and for development without a key.
// It answers from the menu it is given -- rice and chicken adobo when the
// food list has them -- plus one item that is never on the menu, so the
// confirm screen's "not in FitSync's list" card can be seen in dev.
const MODEL = 'stub';

async function recognize({ menuNames }) {
  const has = (n) => menuNames.includes(n);
  const items = [];
  if (has('White rice')) {
    items.push({
      menu: 'White rice', name: 'White rice', quantity: 1, unit: 'cup', grams: 160, confidence: 0.95,
      alternatives: ['Garlic fried rice (sinangag)'].filter(has),
    });
  }
  if (has('Chicken adobo')) {
    items.push({
      menu: 'Chicken adobo', name: 'Chicken adobo', quantity: 2, unit: 'piece', grams: 150, confidence: 0.85,
      alternatives: ['Pork adobo', 'Chicken afritada'].filter(has),
    });
  }
  items.push({
    menu: null, name: 'Stub side dish (not on the menu)', quantity: 1, unit: 'tbsp', grams: 15, confidence: 0.4,
    alternatives: [],
  });
  return { items, provider: MODEL };
}

module.exports = { recognize, model: MODEL };
