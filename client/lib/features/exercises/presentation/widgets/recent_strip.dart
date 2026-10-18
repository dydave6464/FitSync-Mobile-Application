import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../domain/exercise.dart';
import '../exercise_thumb.dart';
import '../providers.dart';

/// The exercises the user logged lately, as a row of small cards above the
/// catalogue.
///
/// A shortcut, not content: most workouts repeat most of the last one, and
/// finding Bench press again should not mean searching 1,300 rows for it. So
/// it shows nothing at all until it has something to offer -- no spinner
/// while it loads, no error when it fails, no "nothing yet" for a new user.
/// The catalogue below is the real answer in every one of those cases.
class RecentStrip extends ConsumerWidget {
  const RecentStrip({
    super.key,
    required this.baseUrl,
    required this.onTap,
    required this.isAdded,
  });

  final String baseUrl;

  /// What a card does: pick the exercise into the workout, or take it out.
  final ValueChanged<ExerciseSummary> onTap;

  /// Whether a card's exercise is already in the workout.
  final bool Function(ExerciseSummary exercise) isAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = switch (ref.watch(recentExercisesProvider)) {
      AsyncData(:final value) => value,
      _ => const <ExerciseSummary>[],
    };
    if (recent.isEmpty) return const SizedBox.shrink();

    return Column(
      key: const Key('library.recent'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          // Meaningful text, so text2 rather than the eyebrow's text3, and a
          // header for screen readers moving by heading.
          child: Semantics(
            header: true,
            child: Text(
              'Recent',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.fs.text2,
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // A Row rather than a lazy list: ten cards at most, and a Row sizes
          // itself to its tallest card, so a name wrapping at large text grows
          // the strip instead of being clipped by a fixed height. Stretched to
          // that height, so a one-line name's card matches a two-line one's;
          // IntrinsicHeight is what gives the stretch a height to reach, and
          // costs little over ten cards.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final exercise in recent)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _RecentCard(
                      exercise: exercise,
                      baseUrl: baseUrl,
                      added: isAdded(exercise),
                      onTap: () => onTap(exercise),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.exercise,
    required this.baseUrl,
    required this.added,
    required this.onTap,
  });

  final ExerciseSummary exercise;
  final String baseUrl;
  final bool added;
  final VoidCallback onTap;

  static const _width = 112.0;
  static const _maxWidth = 176.0;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final radius = BorderRadius.circular(FsRadius.md);
    final label = [
      exercise.name,
      'recent',
      if (exercise.contraindicated) 'loads an injury you reported',
      added ? 'added' : 'not added',
    ].join(', ');

    return Semantics(
      key: Key('recent.${exercise.exerciseId}'),
      container: true,
      button: true,
      selected: added,
      label: label,
      // excludeSemantics drops the InkWell's own tap action along with its
      // children, so the card has to offer it, or a screen reader would
      // announce a button that does nothing.
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        // Wider with larger text, up to a limit, so a long name still fits
        // in its two lines; the strip scrolls sideways to make room.
        width: MediaQuery.textScalerOf(context)
            .scale(_width)
            .clamp(_width, _maxWidth),
        child: Material(
          color: added ? t.accent.withValues(alpha: 0.10) : t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: added ? t.accentLine : t.line),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ExerciseThumb(
                        size: 44,
                        baseUrl: baseUrl,
                        thumbnailUrl: exercise.thumbnailUrl,
                        equipment: exercise.equipment,
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: _Mark(selected: added),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (exercise.contraindicated) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.shield_outlined,
                            size: 13,
                            color: t.red,
                          ),
                        ),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          exercise.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The list rows' add/remove mark, shrunk to sit on a card's thumbnail.
class _Mark extends StatelessWidget {
  const _Mark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accent : t.surface2,
        border: Border.all(color: selected ? Colors.transparent : t.line2),
      ),
      child: Icon(
        selected ? Icons.check : Icons.add,
        size: 13,
        color: selected ? t.onAccent : t.text2,
      ),
    );
  }
}
