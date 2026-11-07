'use strict';
const express = require('express');
const { idParam } = require('../lib/admin-params');
const { manilaDay } = require('../lib/manila-day');
const { randomRunningAd, countAd } = require('../db/ads');

/// /api/v1/ads: the ad card free trainees see on Home and Nutrition. Mounted
/// behind requireAuth, so req.user.isPremium is "is Pro now". Pro members get
/// no ad and are never counted.
module.exports = function buildAdsRouter({ pool, storage }) {
  const router = express.Router();

  // One running ad, picked at random per request, or null.
  router.get('/current', async (req, res, next) => {
    try {
      const row = req.user.isPremium ? null : await randomRunningAd(pool, manilaDay());
      const ad = row && {
        id: row.ad_id, title: row.title, imageUrl: storage.url(row.image_url), linkUrl: row.link_url,
      };
      res.json({ data: { ad } });
    } catch (err) {
      next(err);
    }
  });

  // Always 204: the app reports and moves on. Counted only for a free trainee
  // on an ad running today; an unknown id changes nothing.
  for (const kind of ['view', 'tap']) {
    router.post(`/:id/${kind}`, async (req, res, next) => {
      try {
        const adId = idParam(req.params.id);
        if (adId !== null && !req.user.isPremium) await countAd(pool, adId, kind, manilaDay());
        res.status(204).end();
      } catch (err) {
        next(err);
      }
    });
  }

  return router;
};
