import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// Seven individually tickable weekday cells, Monday first.
///
/// Replaces the 1..7 row that filled up to a count. A count cannot say which
/// days are rest days, and the row filled 1..N made the middle of the week
/// unreachable: a user training Monday, Thursday and Saturday could only ask
/// for "three days".
class TrainingDaysRow extends StatelessWidget {
  const TrainingDaysRow({
    super.key,
    required this.selected,
    required this.onChanged,
    this.busyWeekday,
    this.enabled = true,
  });

  /// Chosen weekdays, 1 = Monday .. 7 = Sunday.
  final List<int> selected;

  /// Reports the WHOLE new set, ascending -- the endpoint replaces rather
  /// than patches, so the caller never has to reconstruct it.
  final ValueChanged<List<int>> onChanged;

  /// The weekday whose write is in flight, if any. Its cell stops accepting
  /// taps so a second tap cannot race the first.
  final int? busyWeekday;

  /// Whether the row may be tapped at all.
  ///
  /// False when the caller does not yet know what is stored. [selected] then
  /// renders seven blank cells that read as "none chosen" while the truth is
  /// "not known", and since the endpoint replaces the whole set rather than
  /// patching it, one tap would send a single day and destroy the rest.
  final bool enabled;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final chosen = selected.toSet();

    final row = Row(
      children: [
        for (var weekday = 1; weekday <= 7; weekday += 1) ...[
          if (weekday > 1) const SizedBox(width: 6),
          Expanded(
            child: TrainingDayCell(
              // Not prefixed with the screen: this row is used by the
              // generator AND by the Settings editor, and a 'gen.' key in
              // Settings would be a lie a test would have to repeat.
              key: Key('weekday.$weekday'),
              label: _labels[weekday - 1],
              selected: chosen.contains(weekday),
              busy: busyWeekday == weekday,
              onTap: !enabled || busyWeekday != null
                  ? null
                  : () {
                      final next = chosen.contains(weekday)
                          ? (chosen.toList()..remove(weekday))
                          : (chosen.toList()..add(weekday));
                      next.sort();
                      onChanged(next);
                    },
            ),
          ),
        ],
      ],
    );

    // Dimmed, not just inert: a row that looks live and silently swallows
    // every tap reads as broken. The caller says why alongside it.
    return enabled ? row : Opacity(opacity: 0.4, child: row);
  }
}

/// One weekday. Public so tests can read [selected] rather than infer it from
/// a colour, which would break the moment the palette moves.
class TrainingDayCell extends StatelessWidget {
  const TrainingDayCell({
    super.key,
    required this.label,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? t.accent : t.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: busy
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: selected ? t.onAccent : t.text3,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? t.onAccent : t.text3,
                ),
              ),
      ),
    );
  }
}
