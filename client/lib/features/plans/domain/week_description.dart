import 'dart:math';

import '../../profile/domain/profile.dart';
import 'workout_plan.dart';

/// "Knee (right)", or just "Lower back" where the region has no sides.
///
/// Laterality comes from the catalogue's [InjuryOption.isLateral], never from
/// guessing which regions have sides -- the same rule the onboarding step
/// follows.
///
/// The side is parenthetical rather than a prefix, which is what keeps the
/// name exactly as the catalogue spells it: a prefix reads as a sentence
/// ("Left SI joint") and invites lowercasing the name to match, which mangles
/// every acronym and leaves "Left si joint" sitting next to a non-lateral
/// "Lower back" that kept its capital. It also gives 'both' somewhere
/// grammatical to go -- "Both shoulder" is not English.
///
/// A side this client does not recognise renders no side at all. Falling back
/// to one, as an if/else chain does by construction, names the wrong side of
/// the user's body with complete confidence on the one screen whose job is
/// saying what is being protected.
String injuryLabel(InjuryOption option, SelectedInjury selected) {
  if (!option.isLateral || selected.side == null) return option.name;
  const labels = {'left': 'left', 'right': 'right', 'both': 'both sides'};
  final side = labels[selected.side];
  return side == null ? option.name : '${option.name} ($side)';
}

/// Something a sentence raised that the generator screen does not own.
///
/// Reported as a topic rather than a phrase so the domain says WHAT was
/// mentioned and the widget decides how to word it.
enum WeekTopic {
  /// Derived by the service from goal and fitness level, and shown here only
  /// as a readout.
  sessionLength,

  /// A profile field. The generator reads it server-side; this screen cannot
  /// change it.
  goal,
}

/// What a sentence about the coming week resolved to.
///
/// Every field is nullable or empty rather than defaulted: "understood
/// nothing" has to stay distinguishable from "understood full body", or
/// applying a vague sentence would quietly reset the controls to defaults.
class WeekDescription {
  const WeekDescription({
    this.splitStyle,
    this.daysPerWeek,
    this.injuries = const [],
    this.elsewhere = const [],
  });

  final String? splitStyle;
  final int? daysPerWeek;

  /// Catalogue regions the sentence named, with whatever side it gave them.
  /// These are candidates for the profile, never something sent to the
  /// generator: injuries reach it server-side, which is what stops a client
  /// generating against someone else's.
  final List<SelectedInjury> injuries;

  /// Topics the sentence raised that this screen cannot act on. Reported so
  /// they can be named back rather than silently dropped.
  final List<WeekTopic> elsewhere;

  /// Whether there is anything here to apply. [elsewhere] deliberately does
  /// not count -- it is something to say, not something to change.
  bool get isEmpty =>
      splitStyle == null && daysPerWeek == null && injuries.isEmpty;
}

const _minDays = 1;
const _maxDays = 7;

const _numberWords = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4,
  'five': 5, 'six': 6, 'seven': 7,
};

/// The spellings [composeWeekDescription] writes and [parseWeekDescription]
/// reads, so a composed sentence resolves back to the plan it came from.
const _splitLabels = {
  'full_body': 'full body',
  'push_pull_legs': 'push / pull / legs',
  'upper_lower': 'upper / lower',
  'cardio_core': 'cardio + core',
};

const _goalLabels = {
  'build_muscle': 'build muscle',
  'lose_weight': 'lose fat',
  'improve_endurance': 'improve endurance',
  'general_fitness': 'stay generally fit',
};

/// A count only counts when it is counting sessions: the number has to be
/// followed by days or a week, so the prototype's own "~50 min" is not read
/// as fifty days -- or, worse, as five.
final _daysPattern = RegExp(
  // No \b after the count: "5x a week" has no boundary between the digit and
  // the x, so requiring one there silently drops the whole times-a-week form.
  // The trailing \b on days/week is what keeps "~50 min" out.
  r'\b(\d{1,3}|one|two|three|four|five|six|seven)'
  r'\s*(?:x|times)?\s*(?:a|per)?\s*\b(?:days?|week)\b',
);

final _minutesPattern =
    RegExp(r'\b\d{1,3}\s*(?:min\b|mins\b|minutes\b)|\bminutes?\b|\bhours?\b');

final _goalPattern = RegExp(
  r'\b(?:gain|build|put on)\s+(?:muscle|mass|size)\b'
  r'|\blose\s+(?:weight|fat)\b'
  r'|\bendurance\b|\bstamina\b|\bget\s+fit\b|\btone\s+up\b',
);

final _sidePattern = RegExp(r'\b(left|right|both)\b');

/// Other words for a catalogue region, keyed by the catalogue's own name.
///
/// Every entry is injury language -- a clinical term or an explicit complaint.
/// Bare muscle names are deliberately absent: "abs", "quads" and "hamstrings"
/// are what people say about what they want to TRAIN, and reading "I want to
/// work my abs" as a core injury would block 608 exercises on the strength of
/// an ambition.
///
/// The table is this client's; the regions are the server's. An alias only
/// ever resolves to a catalogue row that already exists, never conjures one.
const _injuryAliases = <String, List<String>>{
  'lower back': [
    'lumbar', 'bad back', 'back pain', 'sore back', 'spine',
    'slipped disc', 'herniated disc', 'sciatica',
  ],
  'shoulder': ['rotator cuff', 'frozen shoulder'],
  'elbow': ['tennis elbow', 'golfers elbow', "golfer's elbow"],
  'wrist': ['carpal tunnel'],
  'knee': ['acl', 'mcl', 'meniscus', 'patella', 'runners knee', "runner's knee"],
  'ankle': ['achilles'],
  'foot': ['plantar fasciitis'],
  'calf': ['shin splints'],
  'hip': ['hip flexor'],
  'neck': ['cervical'],
};

/// A region can be named in order to rule it OUT. Both cues are narrow on
/// purpose.
///
/// This is NOT a general negation test. "my knee is not good" means injured,
/// and reading a bare "not" as absence would drop a real injury -- which errs
/// toward a plan that loads it. Under-reading is the unsafe direction here, so
/// the resolution word has to follow its linking verb immediately: "is fine"
/// rules the region out, "is not fine" does not.
final _absentCue = RegExp(r'\b(?:no|without|used to)\b');
final _resolvedCue = RegExp(
  r'\b(?:is|are|was|were|feels?|felt)\s+(?:fine|ok|okay|healed|recovered|cleared)\b'
  r'|\bno longer\b|\b(?:healed|recovered)\b',
);

/// How far either side of the region a rule-out cue may sit.
///
/// Short before, because an unrelated "no" earlier in the sentence ("I have no
/// time, protect my knee") must not reach it. Longer after, because the
/// resolution follows the region it describes.
const _ruleOutBefore = 16;
const _ruleOutAfter = 30;

/// How far from a region's name a side word may sit and still describe it.
/// Wide enough for "protect my right knee" and "Knee (right)", narrow enough
/// that the next clause's side does not bleed across.
const _sideWindow = 24;

/// Resolves a sentence into what the generator's controls can actually take.
///
/// Pure, and the catalogue is passed in rather than fetched: matching a
/// region has to be done against the live names the server gave, and a unit
/// that reaches for them itself cannot be tested without a network.
///
/// Clamps and falls back rather than rejecting, the same way
/// `app.rules.parameters.derive` does. A sentence is a best effort by
/// definition; refusing the whole thing over one unreadable clause would
/// throw away the parts that did read.
WeekDescription parseWeekDescription(String text, List<InjuryOption> options) {
  final lower = text.toLowerCase();

  return WeekDescription(
    splitStyle: _split(lower),
    daysPerWeek: _days(lower),
    injuries: _injuries(lower, options),
    elsewhere: [
      if (_minutesPattern.hasMatch(lower)) WeekTopic.sessionLength,
      if (_goalPattern.hasMatch(lower)) WeekTopic.goal,
    ],
  );
}

int? _days(String lower) {
  final match = _daysPattern.firstMatch(lower);
  if (match == null) return null;
  final token = match.group(1)!;
  final value = _numberWords[token] ?? int.tryParse(token);
  return value?.clamp(_minDays, _maxDays);
}

/// Most specific first: a sentence naming push and pull is a PPL week even
/// though "legs" also appears in the lower-body vocabulary.
String? _split(String lower) {
  if (lower.contains('ppl') ||
      (lower.contains('push') && lower.contains('pull'))) {
    return 'push_pull_legs';
  }
  if (lower.contains('upper') && lower.contains('lower')) return 'upper_lower';
  if (RegExp(r'full[\s-]?body').hasMatch(lower)) return 'full_body';
  if (lower.contains('cardio') || lower.contains('core')) return 'cardio_core';
  return null;
}

/// The region's own name, or any word the alias table maps onto it.
RegExpMatch? _nameMatch(String lower, InjuryOption option) {
  final canonical = option.name.toLowerCase();
  for (final term in [canonical, ...?_injuryAliases[canonical]]) {
    final match =
        RegExp(r'\b' + RegExp.escape(term) + r's?\b').firstMatch(lower);
    if (match != null) return match;
  }
  return null;
}

/// Whether the sentence names this region in order to dismiss it.
bool _ruledOut(String lower, RegExpMatch name) {
  final before = lower.substring(max(0, name.start - _ruleOutBefore), name.start);
  final after =
      lower.substring(name.end, min(lower.length, name.end + _ruleOutAfter));
  return _absentCue.hasMatch(before) || _resolvedCue.hasMatch(after);
}

List<SelectedInjury> _injuries(String lower, List<InjuryOption> options) {
  final sides = _sidePattern.allMatches(lower).toList();
  final found = <SelectedInjury>[];

  // One pass per option, so a region named twice -- "lumbar / lower back" --
  // is offered once rather than producing two identical Add buttons.
  for (final option in options) {
    final name = _nameMatch(lower, option);
    if (name == null) continue;
    if (_ruledOut(lower, name)) continue;

    // A region the catalogue says has no sides takes none, whatever the
    // sentence says: the server rejects a side on one, and a region group is
    // not what decides it.
    if (!option.isLateral) {
      found.add(SelectedInjury(injuryId: option.injuryId));
      continue;
    }

    found.add(SelectedInjury(
      injuryId: option.injuryId,
      side: _nearestSide(sides, name),
    ));
  }

  return found;
}

/// The closest side word, not the first: "right knee and left shoulder" puts
/// a side on either end of each name, and only proximity tells them apart.
String? _nearestSide(List<RegExpMatch> sides, RegExpMatch name) {
  String? best;
  var bestDistance = _sideWindow;

  for (final side in sides) {
    final distance = side.end <= name.start
        ? name.start - side.end
        : side.start - name.end;
    if (distance >= 0 && distance < bestDistance) {
      bestDistance = distance;
      best = side.group(1);
    }
  }

  return best;
}

/// A catalogue name as it reads inside a sentence.
///
/// "Knee" is a capital only because it heads a list, and "protecting my Knee"
/// is not a sentence anyone writes. A name carrying a capital anywhere past
/// the first letter earned it -- "SI joint", "IT band" -- and is left exactly
/// as the catalogue spells it, which is the whole reason [injuryLabel] does
/// not lowercase in the first place.
String _midSentence(String label) =>
    label.substring(1).contains(RegExp(r'[A-Z]'))
        ? label
        : label[0].toLowerCase() + label.substring(1);

/// Writes the sentence the "From profile" chip fills the box with.
///
/// Uses the same spellings [parseWeekDescription] reads, so the round trip
/// holds: a composed sentence must not resolve into different controls than
/// the plan it was composed from.
///
/// Omits every clause it has no data for rather than naming a default. A
/// sentence that says "3 days" because nothing was known would put words in
/// the user's mouth, and Apply would then act on them.
String composeWeekDescription({
  Profile? profile,
  WorkoutPlan? plan,
  List<InjuryOption> options = const [],
}) {
  final clauses = <String>[];

  final goal = _goalLabels[profile?.mainGoal];
  if (goal != null) clauses.add('I want to $goal');

  final days = plan?.daysPerWeek;
  if (days != null) clauses.add('train $days days a week');

  final split = _splitLabels[plan?.splitStyle];
  if (split != null) clauses.add(split);

  final protecting = [
    for (final selected in profile?.injuries ?? const <SelectedInjury>[])
      for (final option in options)
        if (option.injuryId == selected.injuryId)
          _midSentence(injuryLabel(option, selected)),
  ];
  if (protecting.isNotEmpty) {
    clauses.add('protecting my ${protecting.join(' and ')}');
  }

  return clauses.isEmpty ? '' : '${clauses.join(', ')}.';
}
