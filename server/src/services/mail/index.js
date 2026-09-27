'use strict';
const stub = require('./stub');
const smtp = require('./smtp');
const brevo = require('./brevo');

function createMailService(mailConfig = {}, logger) {
  const mode = mailConfig.mode || 'stub';

  if (mode === 'stub') return stub.create(logger);

  if (mode === 'smtp') {
    const { host, port, user, password, from } = mailConfig.smtp || {};
    const missing = Object.entries({
      SMTP_HOST: host, SMTP_PORT: port, SMTP_USER: user,
      SMTP_PASSWORD: password, MAIL_FROM: from,
    }).filter(([, v]) => !v).map(([k]) => k);
    if (missing.length > 0) {
      throw new Error(`${missing.join(', ')} required when MAIL_MODE=smtp`);
    }
    return smtp.create({ host, port, user, password, from });
  }

  if (mode === 'brevo') {
    const { apiKey, from } = mailConfig.brevo || {};
    const missing = Object.entries({ BREVO_API_KEY: apiKey, MAIL_FROM: from })
      .filter(([, v]) => !v).map(([k]) => k);
    if (missing.length > 0) {
      throw new Error(`${missing.join(', ')} required when MAIL_MODE=brevo`);
    }
    return brevo.create({ apiKey, from });
  }

  throw new Error(`Unsupported MAIL_MODE: ${mode}`);
}

module.exports = { createMailService };
