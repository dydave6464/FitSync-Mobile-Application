'use strict';

// nodemailer is required lazily, inside create(), so development, tests and
// every stub-mode deployment never load it -- the same reason ranker.py
// imports joblib only when a model file actually exists.
function create({ host, port, user, password, from }) {
  const nodemailer = require('nodemailer');
  const transport = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass: password },
  });

  return {
    async send({ to, subject, text }) {
      await transport.sendMail({ from, to, subject, text });
    },
  };
}

module.exports = { create };
