import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../plans/domain/workout_plan.dart';
import '../../domain/active_session.dart';

/// The way out of a linear workout.
///
/// Paging one exercise at a time is the shape people asked for, but it takes
/// away the thing a single scrolling list gave for nothing: starting
/// somewhere other than the front. A busy squat rack should cost one tap, not
/// three taps of Continue past exercises nobody did. This is that tap.
///
/// Pops the index to move to, or null when dismissed without choosing.
class ExerciseJumpSheet extends StatelessWidget {
  const ExerciseJumpSheet({
    super.key,
    required this.exercises,
    required this.session,
    required this.currentIndex,
  });

  final List<PlanExercise> exercises;

  /// Null only in the gap between a session closing and the route popping,
  /// where every exercise correctly reads as having nothing logged.
  final ActiveSession? session;

  final int currentIndex;

  int _doneCount(int exerciseId) {
    final current = session;
    if (current == null) return 0;
    return current.sets.where((set) => set.exerciseId == exerciseId).length;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 16),
              decoration: BoxDecoration(
                color: t.line2,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Jump to an exercise',
              style: theme.textTheme.titleLarge,
            ),
          ),
          for (var i = 0; i < exercises.length; i++) _row(context, i),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final t = context.fs;
    final exercise = exercises[i];
    final done = _doneCount(exercise.exerciseId);
    final complete = done >= exercise.targetSets;
    final current = i == currentIndex;

    return InkWell(
      key: Key('jump.${exercise.exerciseId}'),
      onTap: () => Navigator.of(context).pop(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        color: current ? t.accentDim : null,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontFamily: fsMonoFamily,
                  fontSize: 12,
                  color: current ? t.accent : t.text3,
                ),
              ),
            ),
            Expanded(
              child: Text(
                exercise.name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  color: t.text,
                ),
              ),
            ),
            Text(
              '$done/${exercise.targetSets}',
              style: TextStyle(
                fontFamily: fsMonoFamily,
                fontSize: 12,
                color: complete ? t.accent : t.text3,
              ),
            ),
            SizedBox(
              width: 26,
              child: complete
                  ? Icon(Icons.check, size: 15, color: t.accent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
