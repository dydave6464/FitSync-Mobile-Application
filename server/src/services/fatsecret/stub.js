'use strict';

/// A fixed handful of foods so tests and offline demos behave the same every
/// time. The ids are invented; nothing here ever reaches FatSecret.
/// Like the real client, search() leaves fiber, sugar and sodium unknown (the
/// description line has none of them) and only get() carries them.
const FOODS = [
  {
    externalId: 'stub-1', name: 'Banana', servingDesc: '1 medium', kcal: 105, proteinG: 1.29, carbsG: 26.95, fatG: 0.39,
    fiberG: 3.1, sugarG: 14.43, sodiumMg: 1.2,
  },
  {
    externalId: 'stub-2', name: 'Fried Chicken', servingDesc: '1 thigh', kcal: 238, proteinG: 18.4, carbsG: 7.85, fatG: 14.5,
    fiberG: 0.5, sugarG: 0, sodiumMg: 386,
  },
  {
    externalId: 'stub-3', name: 'White Rice', servingDesc: '1 cup', kcal: 205, proteinG: 4.25, carbsG: 44.51, fatG: 0.44,
    fiberG: 0.6, sugarG: 0.08, sodiumMg: 1.6,
  },
];

module.exports = {
  async search(q) {
    const needle = String(q).toLowerCase();
    return FOODS.filter((f) => f.name.toLowerCase().includes(needle))
      .map((f) => ({ ...f, fiberG: null, sugarG: null, sodiumMg: null }));
  },
  async get(externalId) {
    const found = FOODS.find((f) => f.externalId === externalId);
    return found ? { ...found } : null;
  },
};
