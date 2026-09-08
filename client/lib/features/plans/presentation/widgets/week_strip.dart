import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// Which weekdays a plan of [daysPerWeek] days is drawn on.
///
/// `workout_plans` stores how many days, never which ones — assigning weekdays
/// is a schema change this slice deliberately does not make. So the strip
/// derives them from a fixed table, spacing rest days as evenly as seven days
/// allow. It is a display convention, not a promise: nothing stops the user
/// training on a different day, and nothing nags them for missing one.
List<int> trainingWeekdays(int daysPerWeek) {
  const table = <int, List<int>>{
    1: [DateTime.wednesday],
    2: [DateTime.monday, DateTime.thursday],
    3: [DateTime.monday, DateTime.wednesday, DateTime.friday],
    4: [DateTime.monday, DateTime.tuesday, DateTime.thursday, DateTime.friday],
    5: [
      DateTime.monday, DateTime.tuesday, DateTime.wednesday,
      DateTime.friday, DateTime.saturday,
    ],
    6: [
      DateTime.monday, DateTime.tuesday, DateTime.wednesday,
      DateTime.thursday, DateTime.friday, DateTime.saturday,
    ],
    7: [1, 2, 3, 4, 5, 6, 7],
  };
  // days_per_week is a plain INT with no CHECK constraint. A bad row should
  // render a sensible week, not crash the tab.
  return table[daysPerWeek] ?? table[3]!;
}

/// One cell. Public so tests can read its flags rather than infer them from
/// colours, which would break the moment the palette moves.
class WeekDayCell extends StatelessWidget {
  const WeekDayCell({
    super.key,
    required this.label,
    required this.prescribed,
    required this.completed,
    required this.isToday,
  });

  final String label;
  final bool prescribed;
  final bool completed;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isToday ? t.accent : t.surface,
          borderRadius: BorderRadius.circular(FsRadius.md),
          border: Border.all(color: isToday ? Colors.transparent : t.line),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isToday ? t.onAccent : t.text3,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 6,
              width: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: completed
                      ? (isToday ? t.onAccent : t.accent)
                      : prescribed
                          ? (isToday ? t.onAccent.withValues(alpha: 0.45)
                                     : t.line2)
                          : Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.daysPerWeek,
    required this.completedDates,
    required this.today,
  });

  final int daysPerWeek;

  /// `YYYY-MM-DD` for every completed session since Monday.
  final Set<String> completedDates;

  final DateTime today;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  static String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final prescribed = trainingWeekdays(daysPerWeek).toSet();
    final monday = today.subtract(Duration(days: today.weekday - 1));

    return Row(
      children: [
        for (var offset = 0; offset < 7; offset++)
          Builder(builder: (_) {
            final date = monday.add(Duration(days: offset));
            final weekday = offset + 1;
            return WeekDayCell(
              key: Key('day.$weekday'),
              label: _labels[offset],
              prescribed: prescribed.contains(weekday),
              // A day the user trained fills even when it was not prescribed:
              // the strip reports what happened, not only what was asked for.
              completed: completedDates.contains(_key(date)),
              isToday: weekday == today.weekday,
            );
          }),
      ],
    );
  }
}
