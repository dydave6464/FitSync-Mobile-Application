'use strict';

// FitSync's own ads (advertisements, 006 + 046). image_url holds a storage
// key; callers turn it into a URL. Days are Manila YYYY-MM-DD strings.

const SELECT_AD = `
  SELECT ad_id, title, image_url, link_url, advertiser, amount_php, is_active, views, taps,
         DATE_FORMAT(starts_on, '%Y-%m-%d') AS starts_on, DATE_FORMAT(ends_on, '%Y-%m-%d') AS ends_on
    FROM advertisements`;

/// An ad's status on [today], first match wins: paused (inactive), scheduled
/// (before its start), ended (after its end), else running.
function adStatus(row, today) {
  if (!row.is_active) return 'paused';
  if (row.starts_on && today < row.starts_on) return 'scheduled';
  if (row.ends_on && today > row.ends_on) return 'ended';
  return 'running';
}

/// A SELECT_AD row in Appendix A's admin ad shape.
function asAdminAd(row, toUrl, today) {
  return {
    id: row.ad_id,
    title: row.title,
    imageUrl: toUrl(row.image_url),
    linkUrl: row.link_url,
    advertiser: row.advertiser,
    amountPhp: Number(row.amount_php),
    startsOn: row.starts_on,
    endsOn: row.ends_on,
    active: Boolean(row.is_active),
    status: adStatus(row, today),
    views: row.views,
    taps: row.taps,
  };
}

/// Every ad, newest first (few ads: no paging).
async function listAds(pool) {
  const [rows] = await pool.query(`${SELECT_AD} ORDER BY created_at DESC, ad_id DESC`);
  return rows;
}

async function findAd(pool, adId) {
  const [rows] = await pool.query(`${SELECT_AD} WHERE ad_id = ?`, [adId]);
  return rows[0] || null;
}

/// Inserts a checked ad (active) and answers its id.
async function insertAd(pool, ad, adminId) {
  const [r] = await pool.query(
    `INSERT INTO advertisements (title, image_url, link_url, advertiser, amount_php, starts_on, ends_on, added_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [ad.title, ad.imageKey, ad.linkUrl, ad.advertiser, ad.amountPhp, ad.startsOn, ad.endsOn, adminId],
  );
  return r.insertId;
}

const COLUMN = {
  title: 'title',
  imageKey: 'image_url',
  linkUrl: 'link_url',
  advertiser: 'advertiser',
  amountPhp: 'amount_php',
  startsOn: 'starts_on',
  endsOn: 'ends_on',
  active: 'is_active',
};

/// Sets the checked [changes] (COLUMN's keys) on an ad; nothing to set is a
/// no-op.
async function updateAd(pool, adId, changes) {
  const keys = Object.keys(changes).filter((k) => Object.hasOwn(COLUMN, k));
  if (keys.length === 0) return;
  await pool.query(
    `UPDATE advertisements SET ${keys.map((k) => `${COLUMN[k]} = ?`).join(', ')} WHERE ad_id = ?`,
    [...keys.map((k) => changes[k]), adId],
  );
}

/// The ads that start in Manila month [month] ('YYYY-MM') -- their amounts
/// count as that month's ad revenue -- by start day, then id.
async function listAdsForMonth(pool, month) {
  const [rows] = await pool.query(
    `${SELECT_AD} WHERE DATE_FORMAT(starts_on, '%Y-%m') = ? ORDER BY starts_on, ad_id`, [month],
  );
  return rows.map((r) => ({
    adId: r.ad_id,
    advertiser: r.advertiser,
    title: r.title,
    amountPhp: Number(r.amount_php),
    startsOn: r.starts_on,
    endsOn: r.ends_on,
  }));
}

module.exports = {
  adStatus, asAdminAd, listAds, findAd, insertAd, updateAd, listAdsForMonth,
};
