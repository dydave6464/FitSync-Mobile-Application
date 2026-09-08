import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../plans/domain/workout_plan.dart';
import '../../domain/active_session.dart';
import 'set_row.dart';

/// One exercise in the scrolling logger: collapsed to a progress line, or
/// expanded into its set table.
///
/// The scrolling shape is a deliberate departure from the mockup's paged
/// logger — see section 5 of the design. It is what lets someone whose squat
/// rack is busy start elsewhere without swiping past four screens.
class ExerciseLogCard extends StatelessWidget {
  const ExerciseLogCard({
    super.key,
    required this.exercise,
    required this.expanded,
    required this.session,
    required this.onExpand,
    required this.onCompleteSet,
    required this.onUndoSet,
    this.last,
  });

  final PlanExercise exercise;
  final bool expanded;
  final ActiveSession? session;
  final LastPerformance? last;
  final VoidCallback onExpand;
  final Future<void> Function(int setNumber, double? weightKg, int? reps) onCompleteSet;
  final Future<void> Function(int setNumber) onUndoSet;

  int get _doneCount {
    final current = session;
    if (current == null) return 0;
    return current.sets.where((set) => set.exerciseId == exercise.exerciseId).length;
  }

  /// How much heavier this session's best set is than the last session's, or
  /// null when there is nothing to compare or nothing to celebrate.
  ///
  /// Strictly greater: equalling last week is not progressive overload, and a
  /// nudge that fires every session stops meaning anything.
  double? get _overload {
    final previous = last?.weightKg;
    final current = session;
    if (previous == null || current == null) return null;

    double? best;
    for (final set in current.sets) {
      if (set.exerciseId != exercise.exerciseId || set.weightKg == null) continue;
      if (best == null || set.weightKg! > best) best = set.weightKg;
    }
    if (best == null || best <= previous) return null;
    return best - previous;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return FsCard(
      key: Key('logcard.${exercise.exerciseId}'),
      small: true,
      onTap: expanded ? null : onExpand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      '${exercise.targetSets} × ${exercise.targetReps}',
                      style: TextStyle(
                        fontFamily: fsMonoFamily,
                        fontSize: 11,
                        color: t.text3,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$_doneCount/${exercise.targetSets}',
                style: TextStyle(
                  fontFamily: fsMonoFamily,
                  fontSize: 11.5,
                  color: _doneCount >= exercise.targetSets ? t.accent : t.text3,
                ),
              ),
            ],
          ),
          if (expanded) ...[
            if (last != null && last!.weightKg != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last ${_trim(last!.weightKg!)} kg'
                '${last!.reps != null ? ' × ${last!.reps}' : ''}',
                style: TextStyle(fontSize: 11, color: t.text2),
              ),
            ],
            if (_overload != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(
                  color: t.accentDim,
                  borderRadius: BorderRadius.circular(FsRadius.sm),
                  border: Border.all(color: t.accentLine),
                ),
                child: Row(
                  children: [
                    Icon(Icons.trending_up, size: 15, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      '+${_trim(_overload!)} kg vs last session',
                      style: TextStyle(fontSize: 11, color: t.text),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            for (var setNumber = 1; setNumber <= exercise.targetSets; setNumber++)
              SetRow(
                // Keyed on the stored set's presence so the row rebuilds its
                // controllers when a set is ticked or un-ticked, rather than
                // keeping stale text.
                key: ValueKey(
                  'set-${exercise.exerciseId}-$setNumber-'
                  '${session?.setFor(exercise.exerciseId, setNumber) != null}',
                ),
                setNumber: setNumber,
                logged: session?.setFor(exercise.exerciseId, setNumber),
                prefillWeightKg: last?.weightKg,
                onComplete: (weightKg, reps) => onCompleteSet(setNumber, weightKg, reps),
                onUndo: () => onUndoSet(setNumber),
              ),
          ],
        ],
      ),
    );
  }

  static String _trim(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}
