'use strict';
const crypto = require('node:crypto');
const express = require('express');
const AppError = require('../lib/app-error');
const { invalidAdminField, idParam, bodyOf } = require('../lib/admin-params');
const { isRealDay } = require('../lib/days');
const { checkImage } = require('../lib/image-check');
const { manilaDay } = require('../lib/manila-day');
const {
  asAdminAd, listAds, findAd, insertAd, updateAd,
} = require('../db/ads');

const MAX_TITLE = 80;
const MAX_ADVERTISER = 120;
const MAX_AMOUNT_PHP = 1_000_000;
const MAX_LINK = 500;

function noSuchAd() {
  return AppError.notFound('AD_NOT_FOUND', 'No such ad.');
}

/// A trimmed name of 1 to [max] characters.
function checkText(field, value, max) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length < 1 || text.length > max) {
    throw invalidAdminField(field, `${field} must be 1 to ${max} characters.`);
  }
  return text;
}

/// Pesos, 0 to MAX_AMOUNT_PHP, to the centavo.
function checkAmount(value) {
  const ok = typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= MAX_AMOUNT_PHP
    && Math.abs(Math.round(value * 100) - value * 100) < 1e-6;
  if (!ok) throw invalidAdminField('amountPhp', `amountPhp must be 0 to ${MAX_AMOUNT_PHP}, to the centavo.`);
  return Math.round(value * 100) / 100;
}

/// A real day as YYYY-MM-DD (future days allowed).
function checkDay(field, value) {
  if (!isRealDay(value)) throw invalidAdminField(field, `${field} must be a real date as YYYY-MM-DD.`);
  return value;
}

/// An https link, answered as the address URL reads it (url.href), which is
/// what is stored and what the app opens: `https:example.com` becomes
/// `https://example.com/`, and a tab or newline inside is dropped. The
/// MAX_LINK limit is on that stored address. Null, absent or blank is no link.
function checkLink(value) {
  if (value == null || (typeof value === 'string' && value.trim() === '')) return null;
  const bad = () => invalidAdminField('linkUrl', `linkUrl must be an https:// link of at most ${MAX_LINK} characters.`);
  if (typeof value !== 'string') throw bad();
  let url;
  try {
    url = new URL(value.trim());
  } catch {
    throw bad();
  }
  if (url.protocol !== 'https:' || url.hostname === '' || url.href.length > MAX_LINK) throw bad();
  return url.href;
}

/// The checked fields [body] sends (all of them when [required]), as
/// db/ads.js changes. The image is checked last, so a bad field is named
/// before the upload is looked at.
function checkAdFields(body, { required }) {
  const sent = (k) => required || body[k] !== undefined;
  const out = {};
  if (sent('title')) out.title = checkText('title', body.title, MAX_TITLE);
  if (sent('advertiser')) out.advertiser = checkText('advertiser', body.advertiser, MAX_ADVERTISER);
  if (sent('amountPhp')) out.amountPhp = checkAmount(body.amountPhp);
  if (sent('startsOn')) out.startsOn = checkDay('startsOn', body.startsOn);
  if (sent('endsOn')) out.endsOn = checkDay('endsOn', body.endsOn);
  if (body.linkUrl !== undefined) out.linkUrl = checkLink(body.linkUrl);
  else if (required) out.linkUrl = null;
  if (!required && body.active !== undefined) {
    if (typeof body.active !== 'boolean') throw invalidAdminField('active', 'active must be true or false.');
    out.active = body.active;
  }
  return out;
}

function checkRunDates(startsOn, endsOn) {
  if (startsOn && endsOn && endsOn < startsOn) {
    throw invalidAdminField('endsOn', 'endsOn must be on or after startsOn.');
  }
}

/// The admin Ads area. Mounted inside buildAdminRouter, so every route here
/// is already behind requireAdmin. Images go through the storage driver at
/// ads/<uuid>.<jpg|png>; the key is stored, responses carry storage.url(key).
function buildAdminAdsRouter({ pool, storage }) {
  const router = express.Router();
  const toUrl = (key) => storage.url(key);
  const answer = (row) => asAdminAd(row, toUrl, manilaDay());

  /// Stores a checked image and answers its key.
  async function storeImage(body) {
    const { bytes, ext } = checkImage(body, { noun: 'image' });
    const key = `ads/${crypto.randomUUID()}.${ext}`;
    await storage.put(key, bytes, body.mimeType);
    return key;
  }

  /// A file nothing references any more: removed, but a failure to remove
  /// it never fails the request that replaced it.
  async function dropImage(key, req) {
    try {
      await storage.delete(key);
    } catch (err) {
      req.log?.warn({ code: err?.code ?? null }, 'old ad image not deleted');
    }
  }

  router.get('/ads', async (_req, res, next) => {
    try {
      const rows = await listAds(pool);
      res.json({ data: { ads: rows.map(answer) } });
    } catch (err) {
      next(err);
    }
  });

  router.post('/ads', async (req, res, next) => {
    try {
      const body = bodyOf(req);
      const ad = checkAdFields(body, { required: true });
      checkRunDates(ad.startsOn, ad.endsOn);
      const imageKey = await storeImage(body);
      let adId;
      try {
        adId = await insertAd(pool, { ...ad, imageKey }, req.admin.adminId);
      } catch (err) {
        await dropImage(imageKey, req);
        throw err;
      }
      res.status(201).json({ data: { ad: answer(await findAd(pool, adId)) } });
    } catch (err) {
      next(err);
    }
  });

  router.patch('/ads/:id', async (req, res, next) => {
    try {
      const adId = idParam(req.params.id);
      const row = adId === null ? null : await findAd(pool, adId);
      if (!row) throw noSuchAd();
      const body = bodyOf(req);
      const changes = checkAdFields(body, { required: false });
      checkRunDates(changes.startsOn ?? row.starts_on, changes.endsOn ?? row.ends_on);
      const replacing = body.image !== undefined || body.mimeType !== undefined;
      if (replacing) changes.imageKey = await storeImage(body);
      try {
        await updateAd(pool, adId, changes);
      } catch (err) {
        if (replacing) await dropImage(changes.imageKey, req);
        throw err;
      }
      if (replacing) await dropImage(row.image_url, req);
      res.json({ data: { ad: answer(await findAd(pool, adId)) } });
    } catch (err) {
      next(err);
    }
  });

  return router;
}

module.exports = { buildAdminAdsRouter };
