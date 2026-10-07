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

  final done = exercises.where(complete).length;
  if (done == exercises.length) {
    return const Encouragement(
      headline:
          'Every set done — great session! Tap Finish session to save it.',
    );
  }

  final next = index + 1 < exercises.length
      ? 'Up next: ${exercises[index + 1].name}'
      : null;

  // Rounded up, so five exercises are halfway at three rather than at two
  // and a half.
  if (done == (exercises.length + 1) ~/ 2) {
    return Encouragement(
      headline:
          "Halfway there — $done of ${exercises.length} exercises done. "
          "You're doing great!",
      detail: next,
    );
  }

  final sets = exercise.targetSets == 1
      ? '1 set'
      : 'all ${exercise.targetSets} sets';
  return Encouragement(
    headline: '${exercise.name} done — $sets. Nice work, keep it up!',
    detail: next,
  );
}
