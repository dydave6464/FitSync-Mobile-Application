import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../exercises/presentation/providers.dart';
import '../../../exercises/presentation/widgets/exercise_demo_body.dart';
import '../../../plans/domain/workout_plan.dart';

/// The mockup's screen 3: what the movement looks like, and how to do it,
/// shown before its set table rather than behind a thumbnail nobody taps.
///
/// A stage of the logger, not a route -- see the design, §5.
///
/// The cues are the catalogue's, carried by `/exercises/:id`. That is a
/// request the logger did not make before this branch: one per exercise
/// entered, not a fetch the screen was already making. What makes it worth
/// paying is that it is cached by `exerciseDetailProvider` for the rest of
/// the session, never blocks the set table behind it -- Start logging is
/// live whatever this shows -- and has its own error branch below, so a
/// catalogue that will not answer costs the cues and nothing else.
///
/// Deliberately not a replacement for [InSessionExerciseScreen]
/// (`../in_session_exercise_screen.dart`), which stays: the set table's
/// thumbnail still pushes that route for a second look at the demo without
/// leaving the table's stage behind.
class ExerciseDemoStage extends ConsumerWidget {
  const ExerciseDemoStage({
    super.key,
    required this.exercise,
    required this.position,
    required this.total,
  });

  final PlanExercise exercise;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final detail = ref.watch(exerciseDetailProvider(exercise.exerciseId));
    // animationUrl is a server-relative '/storage/...' key; without the base
    // URL it resolves to "null/storage/..." and falls through to the
    // equipment icon.
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;

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
        header: Row(
          children: [
            // Not FsEyebrow: that widget forces its text to uppercase, which
            // would render "EXERCISE 1 / 6" instead of the position counter's
            // actual wording. The eyebrow *style* still applies via
            // fsEyebrow(t).
            //
            // `n / N`, matching the meta row's counter directly above this
            // stage on the logger -- the two are on screen together, and two
            // spellings of one number read as two different numbers.
            Text('Exercise $position / $total', style: fsEyebrow(t)),
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
