'use strict';

/// What Pro costs, in one place: GET /pro sends the prices to the app, and
/// checkout charges them whatever the app sends. The prototype's prices
/// (ScreenSubscription): ₱249 a month, or ₱149 a month billed yearly.
/// [name] is the line item on PayMongo's page.
const PLANS = {
  monthly: { pricePhp: 249, months: 1, name: 'FitSync Pro — 1 month' },
  annual: { pricePhp: 1788, months: 12, name: 'FitSync Pro — 1 year' },
};

module.exports = { PLANS };
