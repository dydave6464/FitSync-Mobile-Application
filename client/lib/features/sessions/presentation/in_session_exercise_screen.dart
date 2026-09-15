import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../plans/domain/workout_plan.dart';
import 'widgets/exercise_demo_stage.dart';

/// The demo and cues, mid-workout, as a pushed route.
///
/// Reached from the set table's thumbnail: a second look at a movement
/// without leaving the table's stage behind. The logger opens every exercise
/// on the same demo before its table -- this is the detour back to it, not a
/// duplicate of it.
///
/// Which is why the demo itself is [ExerciseDemoStage] and not a copy of one.
/// This screen is the Scaffold, the app bar and the button back; everything
/// inside -- the fetch, the spinner, the error copy, the header -- is the
/// stage's, shared with the logger. The same relationship [ExerciseDemoBody]
/// has with `ExerciseDetailScreen`, one layer up.
class InSessionExerciseScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = context.fs;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('How to')),
      body: ExerciseDemoStage(
        exercise: exercise,
        // "of", not the logger's "n / N". This is a route of its own with no
        // second counter on screen to agree with, where the logger's stage
        // sits directly beneath a meta row carrying the same number.
        positionLabel: 'Exercise $position of $total',
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
