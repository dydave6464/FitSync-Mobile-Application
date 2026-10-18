import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../domain/exercise.dart';
import '../exercise_thumb.dart';
import '../providers.dart';

/// The exercises the user logged lately, as cards above the catalogue: as
/// many as fit one row, the rest a tap away under "Show all".
///
/// A shortcut, not content: most workouts repeat most of the last one, and
/// finding Bench press again should not mean searching 1,300 rows for it. So
/// it shows nothing at all until it has something to offer -- no spinner
/// while it loads, no error when it fails, no "nothing yet" for a new user.
/// The catalogue below is the real answer in every one of those cases.
///
/// It never scrolls sideways. It did, and on a phone the card cut off at the
/// right-hand edge read as broken, and a swipe from it was the phone's own
/// Back gesture -- the same lesson the muscle buttons taught, which wrap.
class RecentStrip extends ConsumerStatefulWidget {
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
  ConsumerState<RecentStrip> createState() => _RecentStripState();
}

class _RecentStripState extends ConsumerState<RecentStrip> {
  bool _expanded = false;

  static const _side = 16.0;
  static const _gap = 8.0;

  /// Three at most: the cards keep their size rather than shrinking to fit
  /// more, and the latest three are most of what a repeat workout needs.
  static const _mostPerRow = 3;

  @override
  Widget build(BuildContext context) {
    final recent = switch (ref.watch(recentExercisesProvider)) {
      AsyncData(:final value) => value,
      _ => const <ExerciseSummary>[],
    };
    if (recent.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        // As many cards as fit at their least width, which grows with the
        // text, so large text gets fewer and wider cards rather than names
        // squeezed into a sliver.
        final least = MediaQuery.textScalerOf(context)
            .scale(_RecentCard.leastWidth)
            .clamp(_RecentCard.leastWidth, _RecentCard.mostWidth);
        final room = box.maxWidth - 2 * _side;
        final perRow = ((room + _gap) / (least + _gap)).floor().clamp(
          1,
          _mostPerRow,
        );
        final shown = _expanded ? recent : recent.take(perRow).toList();
        final hidden = recent.length > perRow;

        return Column(
          key: const Key('library.recent'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(_side, 0, 4, 0),
              // A Wrap the card's width: the title and the button share a
              // line, the button at its far right, and only when they cannot
              // does the button move under the title -- never squeezed into
              // half the row with its words broken over two lines.
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // A button's height either way, so the cards do not move
                    // when a list grows past one row.
                    SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1,
                        // Meaningful text, so text2 rather than the
                        // eyebrow's text3, and a header for screen readers
                        // moving by heading.
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
                    ),
                    if (hidden)
                      TextButton(
                        key: const Key('library.recent.more'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(
                          _expanded ? 'Show less' : 'Show all ${recent.length}',
                          semanticsLabel: _expanded
                              ? 'Show fewer recent exercises'
                              : 'Show all ${recent.length} recent exercises',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            for (var start = 0; start < shown.length; start += perRow)
              Padding(
                padding: const EdgeInsets.fromLTRB(_side, 0, _side, _gap),
                // Stretched to the row's tallest card, so a one-line name's
                // card matches a two-line one's; IntrinsicHeight is what
                // gives the stretch a height to reach.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var cell = 0; cell < perRow; cell++) ...[
                        if (cell > 0) const SizedBox(width: _gap),
                        Expanded(
                          child: start + cell < shown.length
                              ? _RecentCard(
                                  exercise: shown[start + cell],
                                  baseUrl: widget.baseUrl,
                                  added: widget.isAdded(shown[start + cell]),
                                  onTap: () =>
                                      widget.onTap(shown[start + cell]),
                                )
                              // An empty cell keeps a short last row's cards
                              // the width of the rows above.
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
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

  /// The narrowest a card is drawn, and how wide that grows at large text:
  /// enough for a long name in two lines.
  static const leastWidth = 112.0;
  static const mostWidth = 176.0;

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
      // As wide as its cell in the row; the row works out how many fit.
      child: SizedBox(
        width: double.infinity,
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
