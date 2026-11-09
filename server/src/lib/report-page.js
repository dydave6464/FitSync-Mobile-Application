'use strict';
const { escapeHtml } = require('../routes/auth-pages');
const { periodDays } = require('../db/sessions');

/// The coach's report page: a frozen snapshot in, one self-contained HTML
/// page out.
///
/// Its own shell rather than renderPage from routes/auth-pages.js: that one is
/// the plain card the email and password pages share, and restyling it for a
/// report would change all of them. Everything is inline -- CSS, the SVG
/// chart -- and nothing is fetched from anywhere: the page must render on a
/// weak connection, and a coach opening a link should not tell any third party
/// that they did. The one script is same-origin (print.js below), because
/// helmet's CSP refuses inline script.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const PERIOD_NAMES = { week: 'Week', month: 'Month', year: 'Year' };
const DAY_MS = 24 * 60 * 60 * 1000;
const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

const PRINT_SCRIPT_PATH = '/api/v1/reports/print.js';

/// Served by routes/reports.js at PRINT_SCRIPT_PATH. The button ships hidden
/// with a "use your browser's Print" hint beside it; this swaps them, so a
/// browser without script still has a way to a PDF.
const PRINT_SCRIPT = `(function () {
  var button = document.getElementById('print');
  var hint = document.getElementById('print-hint');
  if (!button || typeof window.print !== 'function') return;
  button.hidden = false;
  if (hint) hint.hidden = true;
  button.addEventListener('click', function () { window.print(); });
})();
`;

/// A calendar day as UTC midnight. Takes 'YYYY-MM-DD', or a Date read from a
/// DATE column -- the pool runs with timezone 'Z', so its UTC fields are the day.
function toDay(value) {
  const iso = value instanceof Date ? value.toISOString().slice(0, 10) : String(value).slice(0, 10);
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

/// The Manila calendar day an instant falls on: expires_at is an instant, and
/// the date a coach is told is the one a Philippine calendar shows.
function manilaDayOf(instant) {
  return toDay(new Date(new Date(instant).getTime() + MANILA_OFFSET_MS));
}

const back = (day, n) => new Date(day.getTime() - n * DAY_MS);
const shortDate = (day) => `${MONTHS[day.getUTCMonth()]} ${day.getUTCDate()}`;
const longDate = (day) => `${shortDate(day)}, ${day.getUTCFullYear()}`;
/// Short when in the same year as [ref], with the year otherwise.
const dated = (day, ref) => (day.getUTCFullYear() === ref.getUTCFullYear() ? shortDate(day) : longDate(day));

function rangeLabel(start, end) {
  return start.getUTCFullYear() === end.getUTCFullYear()
    ? `${shortDate(start)} – ${longDate(end)}`
    : `${longDate(start)} – ${longDate(end)}`;
}

/// Kilograms the way the app writes them: 48200 is unreadable, 48.2k is not.
/// Mirrors formatWeightCompact in client/lib/core/units.dart.
function compactKg(kg) {
  const value = Math.round(Number(kg) || 0);
  if (value < 1000) return `${value} kg`;
  return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}k kg`;
}
const compactNumber = (kg) => compactKg(kg).replace(/ kg$/, '');

const plural = (n, word) => `${n} ${word}${Number(n) === 1 ? '' : 's'}`;
const signedPct = (pct) => `${pct >= 0 ? '+' : ''}${pct}%`;

/// What a volume bar is called. Mirrors volumeBucketName in
/// client/lib/features/sessions/domain/volume_labels.dart -- a week by day, a
/// month by the day each five-day span ends, a year by the month most of each
/// span falls in, every other name -- but counted back from [end], the day the
/// report was frozen, not from today. A period it does not know keeps the
/// server's own label.
function bucketName({ period, index, count, fallback, end }) {
  const days = periodDays(period);
  if (!days || count <= 0) return { axis: fallback, full: fallback };

  const width = Math.ceil(days / count);
  const behind = count - 1 - index;
  const spanEnd = back(end, behind * width);
  const earliest = back(end, days - 1);
  const rawStart = back(end, behind * width + width - 1);
  const spanStart = rawStart < earliest ? earliest : rawStart;

  if (width === 1) {
    const weekday = WEEKDAYS[spanEnd.getUTCDay()];
    return { axis: weekday, full: `${weekday}, ${dated(spanEnd, end)}` };
  }

  const full = spanStart.getUTCFullYear() === spanEnd.getUTCFullYear()
    ? `${shortDate(spanStart)} – ${dated(spanEnd, end)}`
    : `${dated(spanStart, end)} – ${dated(spanEnd, end)}`;

  if (period === 'year') {
    const middle = back(end, behind * width + Math.floor(width / 2));
    const month = MONTHS[middle.getUTCMonth()];
    return { axis: behind % 2 === 0 ? month : '', full, month };
  }
  return { axis: shortDate(spanEnd), full };
}

function sortedPoints(bodyWeight) {
  return [...((bodyWeight && bodyWeight.points) || [])]
    .sort((a, b) => String(a.loggedOn).localeCompare(String(b.loggedOn)));
}

/// The window's weight change, or null when the tile has nothing honest to say:
/// fewer than two entries, or a widened series whose entries reach outside the
/// window the page is captioned with.
function weightChange(bodyWeight) {
  if (!bodyWeight || bodyWeight.widened) return null;
  const points = sortedPoints(bodyWeight);
  if (points.length < 2) return null;
  const first = Number(points[0].weightKg);
  const last = Number(points[points.length - 1].weightKg);
  const delta = Math.round((last - first) * 10) / 10;
  const text = delta === 0 ? '0 kg' : `${delta > 0 ? '+' : '−'}${Math.abs(delta)} kg`;
  return { delta: text, fromTo: `${first} → ${last}` };
}

const emptyLine = (text) => `<p class="muted">${escapeHtml(text)}</p>`;
const card = (title, inner) => `<section class="card"><h2>${escapeHtml(title)}</h2>${inner}</section>`;
const row = (left, right) => `<li><span>${escapeHtml(left)}</span><span class="num">${escapeHtml(right)}</span></li>`;

function tile(value, label, note) {
  return `<div class="tile"><p class="v num">${escapeHtml(value)}</p><p class="l">${escapeHtml(label)}</p>`
    + (note ? `<p class="s">${escapeHtml(note)}</p>` : '')
    + '</div>';
}

function header(fullName, period, start, end) {
  return '<header><p class="brand">FitSync</p><h1>Training report</h1>'
    + `<p class="who">${escapeHtml(fullName)} · ${escapeHtml(rangeLabel(start, end))}`
    + ` · ${escapeHtml(PERIOD_NAMES[period] || period)}</p></header>`;
}

/// Volume, sessions and sets always: the summary is always captured. The
/// percentage only when the volume section was shared and has a previous
/// window; "of N planned" only when a plan sets a target; body weight only
/// when weightChange has something to say.
function tiles(period, report) {
  const s = report.summary || {};
  const pct = report.volume && report.volume.change ? report.volume.change.changePct : null;
  const target = s.adherence && typeof s.adherence.target === 'number' ? s.adherence.target : null;
  const change = weightChange(report.bodyWeight);
  const parts = [
    tile(compactKg(s.totalVolumeKg), 'Volume',
      pct === null || pct === undefined ? null : `${signedPct(pct)} vs previous ${period}`),
    tile(String(s.sessionCount ?? 0), 'Sessions', target === null ? null : `of ${target} planned`),
    tile(String(s.setCount ?? 0), 'Sets'),
  ];
  if (change) parts.push(tile(change.delta, 'Body weight', change.fromTo));
  return `<section class="tiles">${parts.join('')}</section>`;
}

/// Above this many bars a value over each one runs into its neighbour's
/// ("38.8k39.1k"), so the values move to a list under the chart instead.
const MAX_LABELLED_BARS = 8;

function volumeChart(period, buckets, end) {
  const n = buckets.length;
  // A dense chart draws in a narrower box: at a 320px phone the card is about
  // 254px wide, so its 11-unit month names render at about 11.6px.
  const dense = n > MAX_LABELLED_BARS;
  const W = dense ? 240 : 320;
  const H = 150;
  const TOP = 18;
  const BOTTOM = 22;
  const plot = H - TOP - BOTTOM;
  const slot = W / n;
  const barW = Math.min(28, slot * 0.6);
  const max = Math.max(...buckets.map((b) => Number(b.volumeKg) || 0));

  const values = [];
  const bars = buckets.map((b, i) => {
    const kg = Number(b.volumeKg) || 0;
    const name = bucketName({ period, index: i, count: n, fallback: b.label, end });
    values.push(`<li><span class="m">${escapeHtml(name.month || name.full)}</span>`
      + ` <span class="num">${escapeHtml(compactNumber(kg))}</span></li>`);
    const h = max > 0 ? Math.round((kg / max) * plot) : 0;
    const x = (i * slot + (slot - barW) / 2).toFixed(1);
    const cx = (i * slot + slot / 2).toFixed(1);
    const y = TOP + plot - h;
    return `<g><title>${escapeHtml(`${name.full}: ${compactKg(kg)}`)}</title>`
      + (h > 0 ? `<rect x="${x}" y="${y}" width="${barW.toFixed(1)}" height="${h}" rx="4"/>` : '')
      + (kg > 0 && !dense ? `<text class="val" x="${cx}" y="${y - 4}" text-anchor="middle">${escapeHtml(compactNumber(kg))}</text>` : '')
      + (name.axis ? `<text x="${cx}" y="${H - 6}" text-anchor="middle">${escapeHtml(name.axis)}</text>` : '')
      + '</g>';
  }).join('');

  return `<svg class="chart${dense ? ' dense' : ''}" viewBox="0 0 ${W} ${H}" role="img"`
    + ` aria-label="Training volume across this ${escapeHtml(period)}">${bars}</svg>`
    + (dense ? `<ol class="vals">${values.join('')}</ol>` : '');
}

/// The direction, not the comparand: previousKg is what the percentage is
/// made of, and a first window has no percentage at all -- "+100%" measured
/// from zero is not a fact about training.
function volumeCard(period, volume, end) {
  const buckets = volume.buckets || [];
  const total = buckets.reduce((sum, b) => sum + (Number(b.volumeKg) || 0), 0);
  const chart = total > 0 ? volumeChart(period, buckets, end) : emptyLine(`No training volume in this ${period}`);

  let direction = '';
  if (volume.change) {
    const pct = volume.change.changePct;
    direction = emptyLine(pct === null || pct === undefined
      ? `No previous ${period} to compare against`
      : `${signedPct(pct)} against the previous ${period}`);
  }
  return card('Training volume', chart + direction);
}

function bodyWeightCard(bodyWeight, end) {
  const points = sortedPoints(bodyWeight);
  if (points.length === 0) return card('Body weight', emptyLine('No weigh-ins in this period'));

  const change = weightChange(bodyWeight);
  const lead = change
    ? `<p class="lead"><span class="num">${escapeHtml(change.delta)}</span>`
      + ` <span class="soft">${escapeHtml(change.fromTo)} kg</span></p>`
    : '';
  const rows = points.map((p) => row(dated(toDay(p.loggedOn), end), `${Number(p.weightKg)} kg`)).join('');
  // The window widened to find enough points to draw: these entries fall
  // outside the caption's dates, and this is the only place that says so.
  const note = bodyWeight.widened
    ? '<p class="note">Fewer than two entries in this window; showing all recent entries.</p>'
    : '';
  return card('Body weight', `${lead}<ul class="rows">${rows}</ul>${note}`);
}

function musclesCard(muscles) {
  if (muscles.length === 0) return card('Muscle balance', emptyLine('No training volume in this period'));
  const top = Math.max(...muscles.map((m) => Number(m.volumeKg) || 0));
  const bars = muscles.map((m) => {
    const kg = Number(m.volumeKg) || 0;
    const pct = top > 0 ? Math.round((kg / top) * 100) : 0;
    return `<li class="bar"><span class="name">${escapeHtml(m.muscle)}</span>`
      + `<span class="track"><span class="fill" style="width:${pct}%"></span></span>`
      + `<span class="num">${escapeHtml(compactKg(kg))}</span></li>`;
  }).join('');
  return card('Muscle balance', `<ul class="bars">${bars}</ul>`);
}

/// A missing figure is left out rather than printed as 0: rows stored before
/// 2026-11-09 may carry only a date and a set count.
function sessionsCard(sessions, end) {
  if (sessions.length === 0) return card('Sessions', emptyLine('No sessions in this period'));
  const items = sessions.map((x) => {
    const day = toDay(x.sessionDate);
    const title = `${WEEKDAYS[day.getUTCDay()]}, ${dated(day, end)} · ${x.planName || 'Workout'}`;
    const facts = [
      x.exerciseCount != null ? plural(x.exerciseCount, 'exercise') : null,
      x.setCount != null ? plural(x.setCount, 'set') : null,
      x.durationMin != null ? `${x.durationMin} min` : null,
      Number(x.totalVolumeKg) > 0 ? compactKg(x.totalVolumeKg) : null,
    ].filter(Boolean).join(' · ');
    return `<li class="session"><p class="t">${escapeHtml(title)}</p>`
      + (facts ? `<p class="d">${escapeHtml(facts)}</p>` : '')
      + '</li>';
  }).join('');
  return card('Sessions', `<ul class="rows sessions">${items}</ul>`);
}

function footer(end, expiresAt) {
  const expires = expiresAt && !Number.isNaN(new Date(expiresAt).getTime())
    ? ` · This link works until ${longDate(manilaDayOf(expiresAt))}`
    : '';
  return '<footer>'
    + `<p>Frozen on ${escapeHtml(longDate(end))}${escapeHtml(expires)}</p>`
    + '<button type="button" class="print" id="print" hidden>Print / Save as PDF</button>'
    + '<p class="hint" id="print-hint">Use your browser\'s Print to save this as a PDF.</p>'
    + '<p>Shared from the FitSync app</p>'
    + '</footer>';
}

const CSS = `
:root{--bg:#F3F5F3;--surface:#FFFFFF;--line:rgba(17,28,23,.09);--text:#0F1613;--text2:#55636B;
--accent:#087530;--fill:#0C9A40;--track:rgba(17,28,23,.07);--btn:#087530;--btn-text:#FFFFFF}
@media (prefers-color-scheme: dark){:root{--bg:#0A0D11;--surface:#11161D;--line:rgba(255,255,255,.07);
--text:#EEF2F5;--text2:#97A3AD;--accent:#7DFF5C;--fill:#7DFF5C;--track:rgba(255,255,255,.07);
--btn:#7DFF5C;--btn-text:#0A0D11}}
*{box-sizing:border-box}
[hidden]{display:none !important}
body{margin:0;background:var(--bg);color:var(--text);
font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;padding:24px 16px 40px}
main{max-width:560px;margin:0 auto}
p{margin:0}
.brand{color:var(--accent);font-weight:800;letter-spacing:.02em;font-size:.875rem}
h1{font-size:1.5rem;line-height:1.25;margin:4px 0}
.who{color:var(--text2);margin-bottom:20px}
.tiles{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
@media (min-width:600px){.tiles{grid-template-columns:repeat(4,minmax(0,1fr))}}
.tile,.card{background:var(--surface);border:1px solid var(--line);border-radius:16px}
.tile{padding:14px}
.tile .v{font-size:1.375rem;font-weight:700;line-height:1.2}
.tile .l{color:var(--text2);font-size:.8125rem;margin-top:2px}
.tile .s{color:var(--accent);font-size:.8125rem;margin-top:2px}
.card{padding:16px;margin-top:12px;break-inside:avoid}
h2{font-size:1.0625rem;line-height:1.3;margin:0 0 10px}
.muted,.soft,.note{color:var(--text2)}
.muted{margin-top:8px}
.note{font-size:.875rem;margin-top:8px}
.lead{font-size:1.125rem;font-weight:700;margin-bottom:6px}
.lead .soft{font-size:.875rem;font-weight:400}
.num{font-variant-numeric:tabular-nums;white-space:nowrap}
ul.rows,ul.bars{list-style:none;margin:0;padding:0}
ul.rows li{display:flex;justify-content:space-between;gap:12px;padding:10px 0;border-top:1px solid var(--line)}
ul.rows li:first-child{border-top:0}
ul.sessions li{display:block}
.session .t{font-weight:600}
.session .d{color:var(--text2);font-size:.875rem;margin-top:2px}
.bar{display:flex;align-items:center;gap:10px;padding:6px 0}
.bar .name{flex:0 0 34%;overflow-wrap:anywhere}
.bar .track{flex:1;height:10px;border-radius:99px;background:var(--track);overflow:hidden}
.bar .fill{display:block;height:100%;background:var(--fill);border-radius:99px}
.chart{display:block;width:100%;height:auto}
.chart rect{fill:var(--fill)}
.chart text{fill:var(--text2);font-size:10px;font-family:inherit}
.chart text.val{fill:var(--text)}
.chart.dense text{font-size:11px}
ol.vals{list-style:none;margin:8px 0 0;padding:0;display:grid;grid-template-columns:repeat(4,1fr);gap:6px 8px;
font-size:.875rem}
ol.vals li{display:flex;flex-direction:column;line-height:1.3}
ol.vals .m{color:var(--text2);font-size:.75rem}
footer{margin-top:24px;color:var(--text2);font-size:.875rem;text-align:center}
footer p+p,footer .print+p{margin-top:8px}
.print{display:inline-block;margin-top:12px;min-height:48px;padding:0 22px;border:0;border-radius:99px;
background:var(--btn);color:var(--btn-text);font:inherit;font-weight:700;cursor:pointer}
.print:focus-visible{outline:3px solid var(--accent);outline-offset:3px}
@media print{:root{--bg:#FFFFFF;--surface:#FFFFFF;--line:#DDDDDD;--text:#000000;--text2:#444444;
--accent:#087530;--fill:#0C9A40;--track:#EEEEEE}
body{padding:0;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.print,.hint{display:none !important}}
`;

function shell({ title, body, printable }) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>${escapeHtml(title)}</title>
<style>${CSS}</style>
</head>
<body>
<main>
${body}
</main>
${printable ? `<script src="${PRINT_SCRIPT_PATH}" defer></script>` : ''}
</body>
</html>`;
}

function renderReportPage({ fullName, period, windowStart, windowEnd, expiresAt, report }) {
  const start = toDay(windowStart);
  const end = toDay(windowEnd);
  const r = report || {};
  const body = [
    header(fullName, period, start, end),
    tiles(period, r),
    r.volume ? volumeCard(period, r.volume, end) : '',
    r.bodyWeight ? bodyWeightCard(r.bodyWeight, end) : '',
    Array.isArray(r.muscles) ? musclesCard(r.muscles) : '',
    Array.isArray(r.sessions) ? sessionsCard(r.sessions, end) : '',
    footer(end, expiresAt),
  ].join('\n');

  // Deliberately generic, with the name in the body only. The designed path
  // for this link is pasting it into a chat app, and chat apps fetch a URL
  // server-side to build a preview card -- which reads <title>.
  return shell({ title: 'Training report', body, printable: true });
}

/// The page an expired or unknown link gets. One function for both, so the
/// two stay byte-identical and a 404 never confirms a token was real.
function renderReportUnavailable(ttlDays) {
  return shell({
    title: 'Report unavailable',
    body: '<header><p class="brand">FitSync</p><h1>Report unavailable</h1></header>'
      + `<p class="muted">This report is no longer available. Links expire ${escapeHtml(ttlDays)} days`
      + ' after they are shared.</p>',
    printable: false,
  });
}

module.exports = {
  renderReportPage, renderReportUnavailable, PRINT_SCRIPT, PRINT_SCRIPT_PATH, compactKg, bucketName,
};
