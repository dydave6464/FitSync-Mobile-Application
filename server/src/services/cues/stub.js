'use strict';

// Deterministic and offline. Every test in this repository runs against this,
// so the text must be stable rather than a random pick, and it names the injury
// so a test can prove which one the gate passed through.
const MODEL = 'stub';

async function generate({ exerciseName, injuryName }) {
  return [
    {
      title: `${injuryName}: keep the joint out of its painful range`,
      detail: `Shorten the range on ${exerciseName} until it is comfortable, `
        + 'then stay there for the whole set.',
    },
    {
      title: 'Control the lowering phase',
      detail: 'Two seconds down keeps tension off the joint at the turnaround.',
    },
    {
      title: 'Stop the set while the form is still clean',
      detail: 'The last ugly rep is where a flare-up starts.',
    },
  ];
}

module.exports = { generate, model: MODEL };
