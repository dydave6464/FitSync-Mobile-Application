import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/providers.dart';
import '../../exercises/presentation/widgets/exercise_demo_body.dart';
import '../../plans/domain/workout_plan.dart';

/// The demo and cues, mid-workout.
///
/// Shares [ExerciseDemoBody] with the Browse tab's detail screen rather than
/// copying it — the only differences are the position counter, the
/// prescription, and a Done button that returns to the logger.
class InSessionExerciseScreen extends ConsumerWidget {
  const InSessionExerciseScreen({
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

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('How to')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
          header: Row(
            children: [
              // Not FsEyebrow: that widget forces its text to uppercase,
              // which would render "EXERCISE 1 OF 6" instead of the
              // position counter's actual wording. The eyebrow *style* --
              // mono, wide tracking -- still applies via fsEyebrow(t).
              Text('Exercise $position of $total', style: fsEyebrow(t)),
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
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: FsButton(
            key: const Key('insession.done'),
            label: 'Back to logging',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}
