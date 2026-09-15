'use strict';

const ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';
const DEFAULT_MODEL = 'llama-3.1-8b-instant';
const TIMEOUT_MS = 4000;

const MIN_CUES = 2;
const MAX_CUES = 3;
// The column widths in 018_exercise_ai_cues.sql. MySQL truncates a longer value
// mid-sentence rather than refusing it, so the check has to happen here. If
// either number moves, move the column with it.
const MAX_TITLE = 120;
const MAX_DETAIL = 400;

// The prompt is where the safety rules live. The gate has already decided this
// movement loads a joint the user told us about; all that is left is to say how
// to perform it anyway, without straying into advice nobody here is qualified
// to give.
const SYSTEM = [
  'You write short coaching cues for weight-training movements.',
  'The person has told us about an injury. Write cues for HOW TO PERFORM the',
  'movement given that injury: positioning, range of motion, tempo, and what to',
  'stop at. Never diagnose, never prescribe treatment or rehabilitation, and',
  'never tell them to see a doctor -- the app says that separately. Never name a',
  'weight, a rep count or a number of sets: those come from their plan and a',
  'number you invent would contradict the prescription shown on the same screen.',
  'Reply as JSON: {"cues":[{"title":"...","detail":"..."}]} with 2 or 3 entries.',
  `Keep each title under ${MAX_TITLE} characters and each detail under ${MAX_DETAIL}.`,
].join(' ');

/// Validates a model reply and returns its cues, or null.
///
/// Exported for its own tests because this is the security boundary: the reply
/// is untrusted text, and the table it lands in has no expiry to correct a bad
/// row later. Anything not exactly right is discarded whole -- a partially
/// salvaged generation is not worth the chance of storing nonsense forever.
function parseReply(raw) {
  if (typeof raw !== 'string' || raw.trim() === '') return null;

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }

  const cues = parsed && parsed.cues;
  if (!Array.isArray(cues)) return null;
  if (cues.length < MIN_CUES || cues.length > MAX_CUES) return null;

  const clean = [];
  for (const cue of cues) {
    if (!cue || typeof cue.title !== 'string' || typeof cue.detail !== 'string') {
      return null;
    }
    const title = cue.title.trim();
    const detail = cue.detail.trim();
    if (title === '' || detail === '') return null;
    if (title.length > MAX_TITLE || detail.length > MAX_DETAIL) return null;
    clean.push({ title, detail });
  }
  return clean;
}

/// [fetchImpl] is injectable so the failure contract below can be tested
/// without a network. Production passes nothing and gets global fetch.
function create({ apiKey, model = DEFAULT_MODEL, fetchImpl = fetch }) {
  async function generate({ exerciseName, muscleGroup, injuryName, reason }) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    try {
      const res = await fetchImpl(ENDPOINT, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model,
          temperature: 0.3,
          max_tokens: 400,
          response_format: { type: 'json_object' },
          messages: [
            { role: 'system', content: SYSTEM },
            {
              role: 'user',
              content: `Exercise: ${exerciseName} (trains ${muscleGroup}). `
                + `Injured region: ${injuryName}. Why it matters: ${reason}.`,
            },
          ],
        }),
      });

      // A 429 is the free tier working exactly as documented, not an incident.
      // It resolves the same way every other failure does.
      if (!res.ok) return null;

      const body = await res.json();
      return parseReply(body?.choices?.[0]?.message?.content);
    } catch {
      // Timeout, abort, DNS, a malformed envelope -- one answer for all of
      // them. A workout is never blocked by Groq.
      return null;
    } finally {
      clearTimeout(timer);
    }
  }

  return { generate, model };
}

module.exports = { create, parseReply, DEFAULT_MODEL, MAX_TITLE, MAX_DETAIL };
