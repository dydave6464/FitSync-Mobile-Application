import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/presentation/exercise_thumb.dart';
import '../../../plans/domain/workout_plan.dart';
import '../../domain/active_session.dart';
import 'set_drafts.dart';
import 'set_row.dart';

/// The exercise on screen in the paged logger: its prescription, what was
/// lifted last time, and its set table.
///
/// Always open. The collapsed state this widget used to carry belonged to the
/// scrolling list it lived in; the logger shows one exercise at a time now,
/// and ExerciseJumpSheet is what reaches the others.
class ExerciseLogPanel extends StatelessWidget {
  const ExerciseLogPanel({
    super.key,
    required this.exercise,
    required this.session,
    required this.onUndoSet,
    required this.drafts,
    this.activeSetNumber,
    this.last,
    this.onOpenDemo,
    this.unit = WeightUnit.kg,
    this.onUnitChanged,
    this.baseUrl = '',
  });

  final PlanExercise exercise;
  final ActiveSession? session;
  final LastPerformance? last;
  final Future<void> Function(int setNumber) onUndoSet;

  /// Where the typed kg and reps live. Owned by the logger screen, because
  /// the footer button reads the active row out of it.
  final SetDrafts drafts;

  /// Which unit every weight here is shown in and typed in.
  final WeightUnit unit;

  /// The set about to be done -- the lowest with nothing stored against it,
  /// or null once the exercise is finished. Handed in rather than worked out
  /// here: the footer button names this same set ("Complete set 3"), and the
  /// logger screen derives it once so the highlighted row and the button
  /// cannot disagree. A panel built without it highlights nothing.
  final int? activeSetNumber;

  /// Resolves the exercise's artwork. Empty renders the equipment-icon
  /// fallback, which is what a panel built without a repository shows.
  final String baseUrl;

  /// The mockup's single mono line under the exercise name.
  String get _targetLine {
    final target = 'Target ${exercise.targetSets} × ${exercise.targetReps}';
    final previous = last?.weightKg;
    if (previous == null) return target;
    return '$target · last ${formatWeightWithUnit(previous, unit)}';
  }

  /// Null renders the header's toggle inert rather than absent, on the same
  /// reasoning as [onOpenDemo] below.
  final ValueChanged<WeightUnit>? onUnitChanged;

  /// Opens the same demo and cues the Browse tab shows, mid-workout. Null
  /// renders the affordance disabled rather than hiding it, so the header
  /// row's layout stays identical whether or not a caller wires it up.
  final VoidCallback? onOpenDemo;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FsCard(
          key: Key('logpanel.${exercise.exerciseId}'),
          // Flush: the mockup's card has no padding of its own, so the header
          // and the table can carry their own and the table can run to the
          // card's edges.
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    InkWell(
                      key: Key('logpanel.demo.${exercise.exerciseId}'),
                      onTap: onOpenDemo,
                      borderRadius: BorderRadius.circular(FsRadius.md),
                      child: ExerciseThumb(
                        size: 54,
                        radius: FsRadius.md,
                        baseUrl: baseUrl,
                        thumbnailUrl: exercise.thumbnailUrl,
                        equipment: exercise.equipment,
                        // The artwork is the way into the demo, so it says so.
                        overlay: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: t.bg.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow,
                            size: 16,
                            color: onOpenDemo == null ? t.text3 : t.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _targetLine,
                            style: TextStyle(
                              fontFamily: fsMonoFamily,
                              fontSize: 11,
                              color: t.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Column(
                  children: [
                    Padding(
                      key: const Key('logpanel.columns'),
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: SetRow.numberWidth,
                            // softWrap off to match .eyebrow's `white-space:
                            // nowrap`: at 10.5px with the eyebrow's tracking,
                            // "SET" otherwise wraps to two lines inside a
                            // 28px column and shoves the table down a row.
                            child: Text(
                              'SET',
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: fsEyebrow(t),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: FsUnitToggle(
                                value: unit,
                                onChanged: onUnitChanged,
                              ),
                            ),
                          ),
                          const SizedBox(width: SetRow.columnGap),
                          Expanded(
                            child: Center(
                              child: Text(
                                'REPS',
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: fsEyebrow(t),
                              ),
                            ),
                          ),
                          const SizedBox(width: SetRow.columnGap),
                          const SizedBox(width: SetRow.tickWidth),
                        ],
                      ),
                    ),
                    for (var setNumber = 1;
                        setNumber <= exercise.targetSets;
                        setNumber++)
                      Builder(builder: (context) {
                        final stored =
                            session?.setFor(exercise.exerciseId, setNumber);
                        // Seed on every build, which is what lets a prefill
                        // arriving from a fetch -- one frame after the table
                        // is first drawn -- still reach the fields.
                        //
                        // Authoritative exactly when the server holds the
                        // set: a stored value corrects the field, a prefill
                        // never does. See SetDrafts.seed.
                        drafts.seed(
                          setNumber: setNumber,
                          weightKg: stored?.weightKg ?? last?.weightKg,
                          reps: stored?.reps ?? last?.reps,
                          unit: unit,
                          authoritative: stored != null,
                        );
                        return SetRow(
                          key: ValueKey('set-${exercise.exerciseId}-$setNumber'),
                          setNumber: setNumber,
                          logged: stored,
                          drafts: drafts,
                          unit: unit,
                          active: setNumber == activeSetNumber,
                          onReopen: () => onUndoSet(setNumber),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_overload != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: t.accentDim,
              borderRadius: BorderRadius.circular(FsRadius.md),
              border: Border.all(color: t.accentLine),
            ),
            child: Row(
              children: [
                Icon(Icons.arrow_upward, size: 16, color: t.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '+${formatWeightWithUnit(_overload!, unit)} vs last session'
                    ' — nice progressive overload.',
                    style: TextStyle(fontSize: 11, color: t.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
