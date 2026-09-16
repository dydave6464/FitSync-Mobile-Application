'use strict';

const ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';
// Groq retired llama-3.1-8b-instant; `GET /v1/models` is the authority on what
// this key can actually reach. Chosen from what is available because cues are
// written ONCE and cached forever, so a more capable model costs almost nothing
// in aggregate -- and in a side-by-side probe this was the only candidate whose
// advice was actually about the injured joint. The smaller gpt-oss-20b and
// qwen3.8-27b both answered a shoulder question with cues about spine position.
// Override with CUES_MODEL if this is ever retired too.
const DEFAULT_MODEL = 'openai/gpt-oss-120b';
const TIMEOUT_MS = 6000;
// Measured, not guessed. gpt-oss emits hidden reasoning tokens before its
// answer; at the default effort one reply spent 328 of them and ran to 799
// total, overrunning a 400 cap and arriving truncated. At 'low' the same reply
// costs 25 reasoning tokens and ~490 total, so 800 leaves real headroom and
// the free tier's 8,000 tokens/minute allows roughly 16 generations a minute.
const MAX_TOKENS = 800;
const REASONING_EFFORT = 'low';

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
          max_tokens: MAX_TOKENS,
          reasoning_effort: REASONING_EFFORT,
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
      const choice = body?.choices?.[0];

      // A reply cut off at the token ceiling is half a sentence of advice. Most
      // fail JSON parsing anyway, but one truncated at a lucky closing brace
      // would parse clean and be stored forever in a table with no expiry.
      // Refuse the whole generation rather than gamble on where it stopped.
      if (choice?.finish_reason === 'length') return null;

      return parseReply(choice?.message?.content);
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
