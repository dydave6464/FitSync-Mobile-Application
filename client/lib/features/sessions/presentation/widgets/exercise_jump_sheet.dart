import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../exercises/presentation/widgets/coaching_tag.dart';
import '../../../plans/domain/workout_plan.dart';
import '../../domain/active_session.dart';

/// Opens [ExerciseJumpSheet] over the logger: resolves to the index chosen,
/// or null when dismissed without choosing.
Future<int?> showExerciseJumpSheet(
  BuildContext context, {
  required List<PlanExercise> exercises,
  required ActiveSession? session,
  required int currentIndex,
}) {
  return showModalBottomSheet<int>(
    context: context,
    // Past the default cap of 9/16 of the screen: a long plan's rows ran off
    // the bottom. The sheet sets its own ceiling.
    isScrollControlled: true,
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => ExerciseJumpSheet(
      exercises: exercises,
      session: session,
      currentIndex: currentIndex,
    ),
  );
}

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

  /// The tallest the sheet grows, as a share of the screen. Enough for about
  /// ten exercises on a small phone before the list scrolls, while a strip of
  /// the workout stays in view above it -- a sheet, not a new screen, and a
  /// tap on that strip closes it.
  static const _maxHeightFraction = 0.85;

  int _doneCount(int exerciseId) {
    final current = session;
    if (current == null) return 0;
    return current.sets.where((set) => set.exerciseId == exerciseId).length;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _maxHeightFraction,
      ),
      child: SafeArea(
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
            // Only the rows scroll; the handle and the title stay put.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    for (var i = 0; i < exercises.length; i++) _row(context, i),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final t = context.fs;
    final exercise = exercises[i];
    final done = _doneCount(exercise.exerciseId);
    final complete = done >= exercise.targetSets;
    final current = i == currentIndex;

    final row = InkWell(
      key: Key('jump.${exercise.exerciseId}'),
      onTap: () => Navigator.of(context).pop(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        color: current ? t.accentDim : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontFamily: fsMonoFamily,
                  fontSize: 12,
                  color: current ? t.accentText : t.text3,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    exercise.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                      color: t.text,
                    ),
                  ),
                  if (exercise.coaching != null) ...[
                    const SizedBox(height: 4),
                    CoachingTag(
                      key: Key('coaching.jump.${exercise.planExerciseId}'),
                      injuryName: exercise.coaching!.injuryName,
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '$done/${exercise.targetSets} sets',
              style: TextStyle(
                fontFamily: fsMonoFamily,
                fontSize: 12,
                color: complete ? t.accentText : t.text3,
              ),
            ),
            SizedBox(
              width: 26,
              child: complete
                  ? Icon(Icons.check, size: 15, color: t.accentText)
                  : null,
            ),
          ],
        ),
      ),
    );
    // A list long enough to scroll opens on the exercise you are on, not on
    // the first: the highlight is no use below the fold.
    return current ? _RevealOnOpen(child: row) : row;
  }
}

/// Scrolls its child into the middle of the enclosing list once, when the
/// sheet opens. A list too short to scroll stays where it is.
class _RevealOnOpen extends StatefulWidget {
  const _RevealOnOpen({required this.child});

  final Widget child;

  @override
  State<_RevealOnOpen> createState() => _RevealOnOpenState();
}

class _RevealOnOpenState extends State<_RevealOnOpen> {
  @override
  void initState() {
    super.initState();
    // After the first layout: before it there is no list extent to move in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scrollable.ensureVisible(context, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
