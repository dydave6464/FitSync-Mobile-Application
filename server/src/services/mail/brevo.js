'use strict';

/// Sends mail through Brevo's transactional email API: one HTTPS request per
/// message, authenticated by an API key (Brevo -> SMTP & API -> API Keys,
/// `xkeysib-...`). The alternative to SMTP for a host that would rather speak
/// HTTPS than hold an SMTP connection.

const ENDPOINT = 'https://api.brevo.com/v3/smtp/email';

/// Long enough for a slow Brevo, short enough that registration never hangs
/// on it -- the same bound the ML client uses.
const REQUEST_TIMEOUT_MS = 10000;

/// `FitSync <hello@fitsync.app>` or a bare `hello@fitsync.app`, as MAIL_FROM
/// is written for SMTP, into the { name, email } Brevo expects. Refused when
/// it holds no address, so a typo stops the server at startup rather than
/// every registration at send time.
function parseFrom(from) {
  const text = String(from ?? '').trim();
  const named = /^(.*?)\s*<([^<>\s]+@[^<>\s]+)>$/.exec(text);
  if (named) {
    const name = named[1].replace(/^"|"$/g, '').trim();
    return name ? { name, email: named[2] } : { email: named[2] };
  }
  if (/^[^<>\s]+@[^<>\s]+$/.test(text)) return { email: text };
  throw new Error('MAIL_FROM must be an email address or "Name <email address>"');
}

function create({ apiKey, from }) {
  const sender = parseFrom(from);

  return {
    async send({ to, subject, text }) {
      let response;
      try {
        response = await fetch(ENDPOINT, {
          method: 'POST',
          headers: {
            'api-key': apiKey,
            'content-type': 'application/json',
            accept: 'application/json',
          },
          body: JSON.stringify({
            sender,
            to: [{ email: to }],
            subject,
            textContent: text,
          }),
          signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        });
      } catch (err) {
        // err.message is fetch's or the timeout's, never the request, so the
        // key cannot leak through it.
        throw new Error(`Brevo request failed: ${err.message}`, { cause: err });
      }

      if (!response.ok) {
        // Brevo explains a refusal in JSON (`{ code, message }`): an unknown
        // key, an unverified sender, an IP it has not authorised yet.
        let reason = '';
        try {
          const body = await response.json();
          reason = body?.message ? `: ${body.message}` : '';
        } catch {
          // An unreadable body still leaves the status to go on.
        }
        throw new Error(`Brevo refused the email (${response.status})${reason}`);
      }
    },
  };
}

module.exports = { create, parseFrom };
