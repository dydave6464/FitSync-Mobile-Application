'use strict';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

// Every query is scoped to live rows. Pending exercises are an admin review
// queue, not catalogue content.
const LIVE = "x.status = 'live'";

// Every `equipment` field this file returns (listExercises, getExerciseById,
// listFilters) is the raw catalogue tag — `e.name`, e.g. 'body weight' or
// 'cable' — not the curated display name a user picks from during
// onboarding. `GET /plans/active` (src/db/plans.js) returns that curated
// name instead (e.g. 'Bodyweight', with 'cable' folded into 'Machines'),
// because that is what the client's plan_energy.dart MET table keys on.
// Nothing today joins these two vocabularies for the same exercise, but a
// future feature — e.g. "browse the catalogue for this plan exercise's
// equipment" — would silently return no results if it queried this file's
// raw tag against the curated name plans.js hands back, or vice versa.

// Resolves a raw catalogue tag to the curated option it was adopted under.
//
// LEFT JOIN, not INNER: a tag with no parent is a curated option itself, or
// one curation never adopted, and both must survive the join.
const EQUIPMENT_PARENT =
  'LEFT JOIN equipment p ON p.equipment_id = e.parent_equipment_id';

const sentenceCase = (text) =>
  text.length === 0 ? text : text[0].toUpperCase() + text.slice(1);

// Whether this exercise loads a region the user has reported an injury in.
//
// A flag, not a filter: the generator refuses these outright, but someone
// picking by hand may have been cleared for one, and 608 rows vanishing with
// no explanation reads as a broken search rather than as protection. The
// caller decides what to do with it.
//
// Selected rather than joined so a row cannot be duplicated by matching two
// injuries at once.
const CONTRAINDICATED = `EXISTS (
         SELECT 1 FROM exercise_contraindications c
           JOIN user_injuries ui ON ui.injury_id = c.injury_id
          WHERE c.exercise_id = x.exercise_id AND ui.user_id = ?
       )`;

/// The flag's SELECT fragment and its parameter, or a constant 0 and none.
///
/// The parameter belongs to the SELECT list, so it binds BEFORE anything in
/// the WHERE clause. Ordering the two the other way round does not error --
/// it silently matches the muscle group against a user id, and a muscle-group
/// list is one parameter that expands to as many values as it holds, so there
/// is no placeholder count to notice the mistake for us.
function contraindicatedSelect(userId) {
  return userId === undefined || userId === null
      ? { sql: '0 AS contraindicated', params: [] }
      : { sql: `${CONTRAINDICATED} AS contraindicated`, params: [userId] };
}

// LIKE reads '%' and '_' as wildcards, so a search term has to be escaped
// before it becomes a pattern: a user typing '%' would otherwise get the whole
// catalogue back under a search box that looks like it filtered, and '_' would
// quietly stand in for any single character ('3_4' matching '3/4 sit-up').
//
// '!' rather than the backslash MySQL defaults to: a backslash's meaning in a
// string literal depends on the NO_BACKSLASH_ESCAPES sql_mode, so escaping
// with one is correct on a server configured the usual way and silently wrong
// on a server that is not. An explicit ESCAPE clause has one meaning
// everywhere.
const LIKE_ESCAPE = '!';

function likeContains(term) {
  return `%${term.replace(/[!%_]/g, (char) => LIKE_ESCAPE + char)}%`;
}

function buildWhere({ muscleGroup, equipment, search }) {
  const clauses = [LIVE];
  const params = [];
  // An empty list is not an empty result: ml/app/rules/splits.py gives the
  // same shape the same meaning -- "Empty means no filter at all: every group
  // is eligible. That is full body." A caller mapping a split day to its
  // groups hands us exactly that, and `IN ()` is a syntax error rather than a
  // query that matches nothing.
  const groups = Array.isArray(muscleGroup) && muscleGroup.length === 0
      ? null
      : muscleGroup;
  if (groups) {
    // `IN (?)`, not `= ?`: a caller filtering a training split passes the
    // whole day's groups as one array, and mysql2 formats an array as a comma
    // list -- a value list here, a syntax error after `=`. A plain string
    // formats as a one-element list, so both shapes share this predicate.
    clauses.push('x.muscle_group IN (?)');
    params.push(groups);
  }
  if (equipment) {
    // The curated name, not the raw catalogue tag. The dataset tags gear as
    // 'ez barbell', 'trap bar', 'smith machine'; onboarding asks for
    // 'Barbell' and 'Machines'. Matching the tag alone offered the user a
    // filter written in the dataset's vocabulary rather than their own, and
    // split one piece of gear across four options.
    //
    // COALESCE reads both: an adopted tag answers to its parent's name, and
    // one curation never adopted still answers to its own. It also catches a
    // parent with no tag of its own -- nothing is tagged 'machines', which
    // exists only to gather cable, smith machine and leverage machine.
    clauses.push('COALESCE(p.name, e.name) = ?');
    params.push(equipment);
  }
  // ANDed with the rest, like every other clause: the search box narrows the
  // filtered list rather than replacing it. Widening it instead would leave
  // the chips lit while the rows stopped obeying them.
  if (search) {
    clauses.push(`x.name LIKE ? ESCAPE '${LIKE_ESCAPE}'`);
    params.push(likeContains(search));
  }
  return { sql: clauses.join(' AND '), params };
}

async function listExercises(pool, options = {}) {
  const { page = 1, limit = DEFAULT_LIMIT, userId = null } = options;
  const { sql: where, params } = buildWhere(options);
  const flag = contraindicatedSelect(userId);
  const offset = (page - 1) * limit;

  const [[{ total }]] = await pool.query(
    `SELECT COUNT(*) AS total
       FROM exercises x
       LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
       ${EQUIPMENT_PARENT}
      WHERE ${where}`,
    params,
  );

  // Ordering by name alone is not stable — the dataset has 6 duplicate names.
  // exercise_id breaks the tie so pages cannot overlap or skip rows.
  const [rows] = await pool.query(
    `SELECT x.exercise_id, x.name, x.muscle_group, e.name AS equipment, x.thumbnail_url,
            ${flag.sql}
       FROM exercises x
       LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
       ${EQUIPMENT_PARENT}
      WHERE ${where}
      ORDER BY x.name ASC, x.exercise_id ASC
      LIMIT ? OFFSET ?`,
    // SELECT params first: see contraindicatedSelect.
    [...flag.params, ...params, limit, offset],
  );

  return { rows, total };
}

const RECENT_DEFAULT_LIMIT = 10;
const RECENT_MAX_LIMIT = 30;

/// The caller's own exercises, newest first by when each was last logged --
/// the picker's "Recent" strip, so someone logging by hand reaches what they
/// actually do without searching for it again.
///
/// A logged set is a ticked one in a session that was not thrown away: an
/// abandoned session is not a training record (see abandonSession), but the
/// workout in progress is, so what you just did shows up at once.
///
/// Through the list query's own WHERE clause, so a demoted or unreviewed
/// exercise never shows here when the list would hide it -- a shortcut into
/// the catalogue must not lead somewhere the catalogue refuses to go.
///
/// set_logs carries no timestamp, so "when" is the session's date, with the
/// newest set row breaking a tie between exercises trained the same day.
/// Aggregated in a derived table and joined after, so each exercise is one row
/// and the outer query never groups over the catalogue columns.
async function listRecentExercises(pool, userId, { limit = RECENT_DEFAULT_LIMIT } = {}) {
  const { sql: where, params } = buildWhere({});
  const flag = contraindicatedSelect(userId);
  const [rows] = await pool.query(
    `SELECT x.exercise_id, x.name, x.muscle_group, e.name AS equipment, x.thumbnail_url,
            ${flag.sql}
       FROM (
         SELECT sl.exercise_id,
                MAX(ws.session_date) AS last_date,
                MAX(sl.set_log_id) AS last_set
           FROM set_logs sl
           JOIN workout_sessions ws ON ws.session_id = sl.session_id
          WHERE ws.user_id = ?
            AND ws.status <> 'abandoned'
            AND sl.is_completed = TRUE
          GROUP BY sl.exercise_id
       ) r
       JOIN exercises x ON x.exercise_id = r.exercise_id
       LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
       ${EQUIPMENT_PARENT}
      WHERE ${where}
      ORDER BY r.last_date DESC, r.last_set DESC
      LIMIT ?`,
    // Placeholders bind in the order they appear: the SELECT list's flag,
    // then the derived table's user, then the WHERE clause. See
    // contraindicatedSelect for what getting this wrong silently does.
    [...flag.params, userId, ...params, limit],
  );
  return rows;
}

async function getExerciseById(pool, exerciseId, userId = null) {
  const flag = contraindicatedSelect(userId);
  const [rows] = await pool.query(
    `SELECT x.exercise_id, x.name, x.muscle_group, e.name AS equipment,
            x.thumbnail_url, x.animation_url,
            ${flag.sql}
       FROM exercises x
       LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
      WHERE x.exercise_id = ? AND ${LIVE}`,
    // SELECT params first: see contraindicatedSelect.
    [...flag.params, exerciseId],
  );
  if (rows.length === 0) return null;

  const [cues] = await pool.query(
    'SELECT cue_text FROM coaching_cues WHERE exercise_id = ? ORDER BY order_no ASC',
    [exerciseId],
  );

  return { ...rows[0], cues: cues.map((c) => c.cue_text) };
}

async function listFilters(pool) {
  const [muscleGroups] = await pool.query(
    `SELECT x.muscle_group AS value, COUNT(*) AS count
       FROM exercises x
      WHERE ${LIVE}
      GROUP BY x.muscle_group
      ORDER BY x.muscle_group ASC`,
  );

  // Grouped by the curated name so the filter speaks the same vocabulary as
  // onboarding: 14 raw tags become 8 options, and every exercise still lands
  // in exactly one of them.
  const [equipment] = await pool.query(
    `SELECT COALESCE(p.name, e.name) AS value,
            COALESCE(p.display_name, e.display_name) AS label,
            COUNT(*) AS count
       FROM exercises x
       JOIN equipment e ON e.equipment_id = x.equipment_id
       ${EQUIPMENT_PARENT}
      WHERE ${LIVE}
      GROUP BY value, label
      ORDER BY value ASC`,
  );

  return {
    muscleGroups,
    // A tag curation never adopted has no display name of its own. Sentence
    // case rather than the raw tag, so 'medicine ball' does not sit in a list
    // of capitalised options looking like a mistake.
    equipment: equipment.map((row) => ({
      value: row.value,
      label: row.label || sentenceCase(row.value),
      count: row.count,
    })),
  };
}

module.exports = {
  DEFAULT_LIMIT,
  MAX_LIMIT,
  RECENT_DEFAULT_LIMIT,
  RECENT_MAX_LIMIT,
  listExercises,
  listRecentExercises,
  getExerciseById,
  listFilters,
};
