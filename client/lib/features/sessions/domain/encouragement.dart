import '../../plans/domain/workout_plan.dart';
import 'active_session.dart';

/// What the logger says once the exercise on screen is fully logged.
class Encouragement {
  const Encouragement({required this.headline, this.detail});

  final String headline;

  /// The exercise that comes next, when there is one to point at.
  final String? detail;
}

/// The message for [exercises]`[index]`, or null while it still has sets
/// left to log.
///
/// Once per exercise rather than once per set: a message on every tick is
/// noise by the third exercise. And it follows the workout's progress --
/// halfway, then done -- so it reads as feedback on this session rather than
/// a slogan that would say the same thing to anyone.
///
/// Each moment has a pool of lines. Which one shows is picked from the
/// exercise's position plus the session, not at random: random would swap
/// the line every time the screen rebuilds (a tap in a field is enough), and
/// this way each exercise in a workout gets a different line while the next
/// workout shifts them along.
Encouragement? encouragementFor({
  required List<PlanExercise> exercises,
  required int index,
  required ActiveSession session,
}) {
  bool complete(PlanExercise exercise) {
    for (var n = 1; n <= exercise.targetSets; n++) {
      if (session.setFor(exercise.exerciseId, n) == null) return false;
    }
    return true;
  }

  final exercise = exercises[index];
  if (!complete(exercise)) return null;

  T pick<T>(List<T> pool) => pool[(session.sessionId + index) % pool.length];

  final done = exercises.where(complete).length;
  if (done == exercises.length) {
    return Encouragement(headline: pick(_finishedLines));
  }

  final next = index + 1 < exercises.length
      ? 'Up next: ${exercises[index + 1].name}'
      : null;

  // Rounded up, so five exercises are halfway at three rather than at two
  // and a half.
  if (done == (exercises.length + 1) ~/ 2) {
    return Encouragement(
      headline: pick(_halfwayLines)(done, exercises.length),
      detail: next,
    );
  }

  return Encouragement(
    headline: pick(_exerciseLines)(
      _SetCount(exercise.name, exercise.targetSets),
    ),
    detail: next,
  );
}

/// The exercise name and its set count, worded the ways the lines need --
/// singular for a one-set exercise, so nothing reads "all 1 sets".
class _SetCount {
  const _SetCount(this.name, this.count);

  final String name;
  final int count;

  /// "3 sets" / "1 set".
  String get sets => count == 1 ? '1 set' : '$count sets';

  /// "all 3 sets" / "1 set".
  String get allSets => count == 1 ? '1 set' : 'all $count sets';

  /// "All 3 sets" / "1 set", for the start of a sentence.
  String get allSetsCapital => count == 1 ? '1 set' : 'All $count sets';
}

/// An exercise finished, more of the workout to go. Every line names the
/// exercise and its sets. The first is the original wording.
final List<String Function(_SetCount)> _exerciseLines = [
  (e) => '${e.name} done — ${e.allSets}. Nice work, keep it up!',
  (e) => "That's ${e.name} finished — ${e.allSets} in the bag.",
  (e) => '${e.name} complete! ${e.sets}, done and dusted.',
  (e) => 'Solid work on ${e.name} — ${e.allSets} logged.',
  (e) => '${e.name}: ${e.count} for ${e.count}. Keep that momentum going!',
  (e) => 'Great effort — ${e.name} is done, ${e.allSets}.',
  (e) => '${e.name} crushed — ${e.sets}. On to the next one!',
  (e) => "${e.allSetsCapital} of ${e.name} done. You're on a roll!",
];

/// The exercise that brings the workout to halfway.
final List<String Function(int done, int total)> _halfwayLines = [
  (done, total) =>
      "Halfway there — $done of $total exercises done. You're doing great!",
  (done, total) =>
      "$done of $total exercises down — you're past the halfway mark!",
  (done, total) => 'Halfway done — $done of $total exercises. Keep pushing!',
];

/// Every set of every exercise logged. Each ends by pointing at Finish,
/// because the session is not saved until it is tapped.
const List<String> _finishedLines = [
  'Every set done — great session! Tap Finish session to save it.',
  "That's the whole workout — well done! Tap Finish session to save it.",
  'Workout complete — you showed up and did the work. '
      'Tap Finish session to save it.',
];
