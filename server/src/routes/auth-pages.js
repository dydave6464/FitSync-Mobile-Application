'use strict';

// Escapes characters that would let a value break out of the HTML context it
// is interpolated into. Anything reaching renderPage's `body` that came from
// a caller (a token, a query string, ...) must be run through this first.
function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[ch]));
}

// One small, self-contained HTML shell for every server-rendered auth page:
// the email-verification result and the password-reset form and its result.
// Inline CSS, no template engine, no external assets or fonts -- these pages
// are opened straight out of a mail client and must render with no network.
function renderPage({ title, body }) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
  body { font-family: system-ui, sans-serif; background: #f5f5f5; margin: 0;
         display: flex; justify-content: center; padding: 48px 16px; }
  main { background: #fff; border-radius: 8px; padding: 32px; max-width: 420px;
         width: 100%; box-shadow: 0 1px 3px rgba(0,0,0,0.1); box-sizing: border-box; }
  h1 { font-size: 1.25rem; margin: 0 0 16px; }
  p { color: #333; line-height: 1.5; }
  label { display: block; font-size: 0.875rem; color: #333; margin-bottom: 4px; }
  input { display: block; width: 100%; box-sizing: border-box; padding: 8px;
          margin: 0 0 16px; border: 1px solid #ccc; border-radius: 4px; font-size: 1rem; }
  button { background: #2563eb; color: #fff; border: none; padding: 10px 16px;
           border-radius: 4px; cursor: pointer; font-size: 1rem; }
</style>
</head>
<body>
<main>
<h1>${escapeHtml(title)}</h1>
${body}
</main>
</body>
</html>`;
}

module.exports = { renderPage, escapeHtml };
