import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../routine/domain/routine.dart';

/// Home's read-only summary of today's routine. Every tap opens the routine
/// screen, the one place items are ticked -- the user chose that over
/// ticking from Home.
class RoutineCard extends StatelessWidget {
  const RoutineCard({
    super.key,
    required this.day,
    required this.onTap,
    this.streak = 0,
    this.onOpenStreak,
  });

  final RoutineDay day;
  final VoidCallback onTap;

  /// Days in a row with any activity. The tag is hidden at 0: the card never
  /// shows a streak the app does not have.
  final int streak;

  /// The tag's own destination; the rest of the card still opens the routine.
  final VoidCallback? onOpenStreak;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final entries = day.entries;

    return FsCard(
      key: const Key('home.routine'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The streak is a small chip, as the design draws it -- a button,
          // and unlike the count tag beside it. The card's padding above and
          // the gap below are the room its 48 dp band reaches into, so a
          // near miss still opens the streak rather than the routine.
          //
          // A Wrap, not a Row, as ProgressSnapshotCard's header: at large
          // text on a small phone the chip and tag left the title too little
          // room and it broke mid-word, or the row overflowed. Now they move
          // under it instead. Card-wide, so spaceBetween has room to use.
          FsTapRoom(
            reach: 11,
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  Text(
                    "Today's routine",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  if (streak >= 1 || entries.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (streak >= 1)
                          FsChip(
                            key: const Key('home.routine.streak'),
                            label: '$streak-day streak',
                            small: true,
                            selected: false,
                            toggle: false,
                            onTap: onOpenStreak,
                          ),
                        if (entries.isNotEmpty)
                          FsTag('${day.done} / ${day.total}'),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              "Nothing on today's routine ›",
              style: TextStyle(fontSize: 13, color: t.text2),
            )
          else ...[
            for (final entry in entries.take(_shown)) ...[
              // The tick box and strike-through are visual only; a screen
              // reader hears the state in words.
              Semantics(
                label: '${entry.title}, ${entry.done ? 'done' : 'not done'}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: entry.done ? t.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        // t.control, as the Routine screen's own tick box:
                        // the outline is what says a box is there (3:1).
                        border: Border.all(
                          color: entry.done ? t.accent : t.control,
                          width: 2,
                        ),
                      ),
                      child: entry.done
                          ? Icon(Icons.check, size: 11, color: t.onAccent)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      // A done item is quieter by colour, not by opacity: the
                      // design's 55% fade took the title under 4.5:1 in light.
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: entry.done ? t.text3 : t.text,
                          decoration: entry.done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (entries.length > _shown)
              Text(
                '+${entries.length - _shown} more',
                key: const Key('home.routine.more'),
                style: TextStyle(fontSize: 11.5, color: t.text3),
              ),
          ],
        ],
      ),
    );
  }
}
