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
  const named = /^(.*?)\s*<\s*([^<>\s]+)\s*>$/.exec(text);
  const email = named ? named[2] : text;
  // One @, and a dot in the domain: enough to stop a typo at startup without
  // pretending to validate every address the RFCs allow.
  if (!/^[^@<>\s]+@[^@<>\s]+\.[^@<>\s]+$/.test(email)) {
    throw new Error('MAIL_FROM must be an email address or "Name <email address>"');
  }
  const name = named ? named[1].trim().replace(/^(["'])(.*)\1$/, '$2').trim() : '';
  return name ? { name, email } : { email };
}

/// Printable ASCII only. fetch echoes an invalid header value -- the whole
/// key -- in its error, so a key pasted with a line break or a stray space
/// would otherwise reach the log on every send. Refused at startup instead,
/// without repeating it.
function checkKey(apiKey) {
  if (!/^[\x21-\x7e]+$/.test(String(apiKey ?? ''))) {
    throw new Error(
      'BREVO_API_KEY contains characters that cannot be sent in a header '
        + '(a line break or space from copying it?)',
    );
  }
}

/// Brevo's own words for a refusal, kept to a readable length.
function reasonFrom(body) {
  const message = body?.message;
  return typeof message === 'string' && message ? `: ${message.slice(0, 200)}` : '';
}

function create({ apiKey, from }) {
  checkKey(apiKey);
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
        // A network failure or the timeout: neither carries request headers.
        // The one fetch error that would -- an invalid header value, which
        // echoes it -- cannot happen, because checkKey refused such a key at
        // startup.
        throw new Error(`Brevo request failed: ${err.message}`, { cause: err });
      }

      if (!response.ok) {
        // Brevo explains a refusal in JSON (`{ code, message }`): an unknown
        // key, an unverified sender, an IP it has not authorised yet.
        let reason = '';
        try {
          reason = reasonFrom(await response.json());
        } catch {
          // An unreadable body still leaves the status to go on.
        }
        throw new Error(`Brevo refused the email (${response.status})${reason}`);
      }
      // The message id in a success body is not needed; releasing the body
      // lets the connection be reused rather than held until collected.
      await response.body?.cancel?.().catch(() => {});
    },
  };
}

module.exports = { create, parseFrom };
