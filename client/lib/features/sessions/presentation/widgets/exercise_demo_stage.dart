import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../exercises/presentation/providers.dart';
import '../../../exercises/presentation/widgets/exercise_demo_body.dart';
import '../../../plans/domain/workout_plan.dart';

/// What the movement looks like and how to do it: the mockup's screen 3.
///
/// The cues are the catalogue's, carried by `/exercises/:id`. That is a
/// request the logger did not make before this branch: one per exercise
/// entered, not a fetch the screen was already making. What makes it worth
/// paying is that it is cached by `exerciseDetailProvider` for the rest of
/// the session, never blocks the set table behind it -- Start logging is
/// live whatever this shows -- and has its own error branch below, so a
/// catalogue that will not answer costs the cues and nothing else.
///
/// Two things wrap this, and it is deliberately neither of them:
///
/// * [SessionLoggerScreen] (`../session_logger_screen.dart`) renders it as a
///   *stage*, before the set table -- not a route, so the session, the drafts
///   and the rest countdown all stay put behind it. See the design, §5.
/// * [InSessionExerciseScreen] (`../in_session_exercise_screen.dart`) pushes
///   it as a route, for the second look the set table's thumbnail offers
///   mid-set.
///
/// Both need the same fetch, the same loading spinner, the same error copy
/// and the same header, and they used to carry a verbatim copy of each. What
/// differs between them is the Scaffold around it and the button below it, so
/// that is what stays out here -- the same relationship [ExerciseDemoBody]
/// already has with `ExerciseDetailScreen`.
class ExerciseDemoStage extends ConsumerWidget {
  const ExerciseDemoStage({
    super.key,
    required this.exercise,
    required this.positionLabel,
  });

  final PlanExercise exercise;

  /// The eyebrow above the name -- "Exercise 2 / 6".
  ///
  /// Passed in rather than formatted from a position and a total, because the
  /// two wrappers above genuinely word it differently: on the logger this
  /// sits directly under a meta row carrying the same counter, and has to
  /// match it exactly (see `_positionLabel` there), while the pushed route
  /// has no second counter to agree with and reads "Exercise 2 of 6".
  final String positionLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final detail = ref.watch(exerciseDetailProvider(exercise.exerciseId));
    // animationUrl is a server-relative '/storage/...' key; without the base
    // URL it resolves to "null/storage/..." and falls through to the
    // equipment icon.
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;
    final cues = ref.watch(exerciseCuesProvider(exercise.exerciseId));

    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // A demo that will not load must not block the workout behind it.
      error: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load this exercise. You can still log your sets.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: t.text2),
          ),
        ),
      ),
      data: (loaded) => ExerciseDemoBody(
        exercise: loaded,
        baseUrl: baseUrl,
        // Null while `/cues` is in flight, and null again if it fails --
        // either way the body falls back to the catalogue cues `loaded`
        // already carries. The reader has usable cues from the first frame,
        // and nothing on screen claims to be AI-written until it is.
        cues: cues.value,
        header: Row(
          children: [
            // Not FsEyebrow: that widget forces its text to uppercase, which
            // would render "EXERCISE 1 / 6" instead of the position counter's
            // actual wording. The eyebrow *style* still applies via
            // fsEyebrow(t).
            Text(positionLabel, style: fsEyebrow(t)),
            const Spacer(),
            Text(
              '${exercise.targetSets} × ${exercise.targetReps}',
              style: TextStyle(
                fontFamily: fsMonoFamily,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
