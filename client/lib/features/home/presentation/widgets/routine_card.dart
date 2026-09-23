import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../routine/domain/routine.dart';

/// Home's read-only summary of today's routine. Every tap opens the routine
/// screen, the one place items are ticked -- the user chose that over
/// ticking from Home.
class RoutineCard extends StatelessWidget {
  const RoutineCard({super.key, required this.day, required this.onTap});

  final RoutineDay day;
  final VoidCallback onTap;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  "Today's routine",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              if (entries.isNotEmpty) FsTag('${day.done} / ${day.total}'),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              "Nothing on today's routine ›",
              style: TextStyle(fontSize: 13, color: t.text2),
            )
          else ...[
            for (final entry in entries.take(_shown)) ...[
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: entry.done ? t.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: entry.done ? t.accent : t.line2,
                        width: 2,
                      ),
                    ),
                    child: entry.done
                        ? Icon(Icons.check, size: 11, color: t.onAccent)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Opacity(
                      opacity: entry.done ? 0.55 : 1,
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: t.text,
                          decoration: entry.done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
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
