'use strict';

// Writes the message to the log instead of sending it. This is a complete
// local flow, not a degraded one: the developer clicks the verification link
// out of the server log. See the design, section 5.
//
// `sent` lets tests assert on a link without a network or a mail server.
function create(logger = console) {
  const sent = [];
  return {
    sent,
    async send(message) {
      sent.push(message);
      const line = `[mail:stub] to=${message.to} subject=${message.subject}\n${message.text}`;
      if (typeof logger.info === 'function') logger.info(line);
      else logger.log(line);
    },
  };
}

module.exports = { create };
