'use strict';

// The share-a-report token is the only credential in this app that rides in
// the URL PATH rather than the query string: GET /api/v1/reports/<43 chars>
// is opened by a coach with no account, so the token IS the credential -- and
// unlike the emailed verify-email and password-reset tokens, it stays live
// for 30 days. Anything that writes a request URL into a log has to put it
// through here first.
//
// Case-INSENSITIVE, and that flag is load-bearing rather than defensive.
// Express leaves `case sensitive routing` disabled by default and this app
// never enables it, so GET /API/V1/Reports/<token> reaches the real
// GET /reports/:token handler and serves the report page. An anchored
// lowercase pattern would miss exactly that request while it succeeded,
// putting a live token in the log at info level on a 200.
//
// The replacement keeps $1 -- the prefix as it was actually written -- so the
// route shape a case-variant request took is still visible in the log. Only
// the token segment is destroyed.
const REPORT_TOKEN_PATH = /^(\/api\/v1\/reports\/)[^/]+/i;

/// [url] with any share-report token in it replaced by a placeholder.
///
/// Returns non-strings untouched, so a caller can hand it whatever a request
/// object happened to carry without guarding first.
function redactUrl(url) {
  if (typeof url !== 'string') return url;
  return url.replace(REPORT_TOKEN_PATH, '$1[REDACTED]');
}

module.exports = { REPORT_TOKEN_PATH, redactUrl };
