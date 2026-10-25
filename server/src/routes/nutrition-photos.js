'use strict';
const express = require('express');
const requireAuth = require('../middleware/require-auth');
const AppError = require('../lib/app-error');
const { matchItems } = require('../lib/photo-match');
const { createMenuCache } = require('../db/vision-menu');
const { countToday, insertFailed, insertRecognition } = require('../db/photo-recognitions');
const { VisionError } = require('../services/vision/errors');

/// Photos per Pro user per Manila day. Groq's free plan allows roughly 45
/// photos a day app-wide with the full menu in each request.
const DAILY_PHOTO_LIMIT = 15;
const MAX_IMAGE_BYTES = 1_500_000;
const MAGIC = {
  'image/jpeg': [0xff, 0xd8, 0xff],
  'image/png': [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
};
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;
const VISION_DOWN = "Couldn't look at your photo right now.";

const badImage = (message) => AppError.badRequest('INVALID_IMAGE', message);

/// Throws INVALID_IMAGE unless the body holds a JPEG or PNG -- by its first
/// bytes, not only its label -- of at most 1.5 MB. Decoded into memory only;
/// nothing here writes it anywhere.
function checkImage(body) {
  const { image, mimeType } = body || {};
  const magic = MAGIC[mimeType];
  if (!magic) throw badImage('mimeType must be image/jpeg or image/png.');
  if (typeof image !== 'string' || image.length === 0 || image.length % 4 !== 0 || !BASE64.test(image)) {
    throw badImage('image must be base64, with no data: prefix.');
  }
  // The encoded length first, so an oversized photo is refused undecoded.
  if (image.length > Math.ceil(MAX_IMAGE_BYTES / 3) * 4) throw badImage('The photo must be at most 1.5 MB.');
  const bytes = Buffer.from(image, 'base64');
  if (bytes.length > MAX_IMAGE_BYTES) throw badImage('The photo must be at most 1.5 MB.');
  if (!magic.every((b, i) => bytes[i] === b)) throw badImage('The photo is not the image type it says it is.');
}

/// A menu food as the app gets it. fromFatsecret: a saved FatSecret copy --
/// logged by its id like any FitSync food, but the numbers are FatSecret's,
/// so the app shows their attribution.
function foodOut(f) {
  return {
    id: f.foodId,
    name: f.name,
    servingDesc: f.servingDesc,
    fromFatsecret: f.externalId != null,
    perServing: {
      kcal: f.kcal, proteinG: f.proteinG, carbsG: f.carbsG, fatG: f.fatG,
      fiberG: f.fiberG, sugarG: f.sugarG, sodiumMg: f.sodiumMg,
    },
  };
}

module.exports = function buildNutritionPhotosRouter(deps) {
  const router = express.Router();
  const auth = requireAuth(deps);
  const { pool } = deps;
  const menu = createMenuCache();

  // Snap a meal is Pro. isPremium is read fresh on every request by
  // requireAuth, so `npm run pro:grant` takes effect at once.
  const requirePro = (req, _res, next) => next(
    req.user.isPremium ? undefined : AppError.forbidden('PRO_REQUIRED', 'Snap a meal is part of FitSync Pro.'),
  );

  router.post('/recognize', auth, requirePro, async (req, res, next) => {
    try {
      checkImage(req.body);
      if (!deps.vision) throw new AppError(502, 'VISION_UNAVAILABLE', VISION_DOWN);
      const { userId } = req.user;
      // Counted before the AI is asked; two photos sent at the same instant
      // can at worst let one extra through.
      const used = await countToday(pool, userId);
      if (used >= DAILY_PHOTO_LIMIT) {
        throw new AppError(429, 'PHOTO_LIMIT_REACHED', "You've used today's meal photos. Try again tomorrow.");
      }
      const foods = await menu.get(pool);
      let reply;
      try {
        reply = await deps.vision.recognize({
          imageBase64: req.body.image, mimeType: req.body.mimeType, menuNames: foods.map((f) => f.name),
        });
      } catch (err) {
        // The service's failure, not the user's: recorded, never counted.
        await insertFailed(pool, userId);
        // Codes only, never a message or a reply body: Groq's status tells a
        // dead key (401) or a retired model (404) from a short outage.
        const isVision = err instanceof VisionError;
        (req.log ?? deps.logger)?.warn({
          code: err?.code ?? null,
          status: err?.status ?? null,
          cause: isVision ? (err.cause?.name ?? null) : (err?.name ?? null),
        }, 'meal photo recognition failed');
        if (isVision && err.code === 'VISION_BUSY') throw new AppError(503, 'VISION_BUSY', VISION_DOWN);
        throw new AppError(502, 'VISION_UNAVAILABLE', VISION_DOWN);
      }
      const { items, unlisted } = matchItems(reply.items, foods);
      const { recognitionId, itemIds } = await insertRecognition(pool, userId, [
        ...items.map((it) => ({
          foodId: it.food.foodId, name: it.food.name, confidence: it.confidence, servings: it.servings,
          alternativeFoodIds: it.alternatives.map((a) => a.foodId),
        })),
        ...unlisted.map((u) => ({ foodId: null, name: u.name, confidence: u.confidence, servings: null, alternativeFoodIds: [] })),
      ]);
      // Ids and counts only: never the photo, never the food names.
      if (deps.logger) deps.logger.info({ recognitionId, items: items.length, unlisted: unlisted.length }, 'meal photo recognised');
      res.json({
        data: {
          recognitionId,
          remainingToday: Math.max(0, DAILY_PHOTO_LIMIT - used - 1),
          items: items.map((it, i) => ({
            itemId: itemIds[i], confidence: it.confidence, servings: it.servings,
            food: foodOut(it.food), alternatives: it.alternatives.map(foodOut),
          })),
          unlisted: unlisted.map((u, i) => ({ itemId: itemIds[items.length + i], name: u.name })),
        },
      });
    } catch (err) { next(err); }
  });

  return router;
};
