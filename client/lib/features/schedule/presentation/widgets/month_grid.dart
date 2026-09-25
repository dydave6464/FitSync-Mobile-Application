import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../domain/calendar.dart';
import '../../domain/schedule_view.dart';

const _weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Six Monday-first weeks around [month], a dot per kind of item under each
/// day, and a legend.
///
/// [days] is null until the range loads, or when it failed: the cells still
/// show, just without dots, so nothing jumps when they arrive.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.dates,
    required this.today,
    required this.days,
    this.selected,
    this.onTapDay,
  });

  final YearMonth month;

  /// The 42 dates, from [monthGridDates].
  final List<String> dates;
  final String today;
  final Map<String, CalendarDay>? days;
  final String? selected;

  /// Null while nothing has loaded: a tap would have nothing to show.
  final ValueChanged<String>? onTapDay;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final tap = onTapDay;
    return Column(
      children: [
        Row(
          children: [
            for (final letter in _weekLetters)
              Expanded(
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: t.text3,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var week = 0; week < 6; week++)
          Row(
            children: [
              for (final date in dates.sublist(week * 7, week * 7 + 7))
                Expanded(
                  child: ScheduleDayCell(
                    key: Key('schedule.day.$date'),
                    date: date,
                    inMonth: monthOf(date) == month,
                    isToday: date == today,
                    selected: date == selected,
                    workout: days?[date] == null
                        ? DotState.none
                        : workoutDot(days![date]!),
                    habits: days?[date] == null
                        ? DotState.none
                        : habitsDot(days![date]!),
                    onTap: tap == null ? null : () => tap(date),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        const _Legend(),
      ],
    );
  }
}

/// One day: its number, today filled with the accent, the selected day
/// outlined, and up to two dots.
class ScheduleDayCell extends StatelessWidget {
  const ScheduleDayCell({
    super.key,
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.workout,
    required this.habits,
    this.onTap,
  });

  final String date;

  /// False for the neighbouring months' days, which are dimmed.
  final bool inMonth;
  final bool isToday;
  final bool selected;
  final DotState workout;
  final DotState habits;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final radius = BorderRadius.circular(9);
    return Opacity(
      opacity: inMonth ? 1 : 0.35,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: isToday ? t.accent : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: selected
                ? BorderSide(color: isToday ? t.text : t.accent, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${int.parse(date.substring(8, 10))}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isToday ? t.onAccent : t.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (workout != DotState.none)
                          ScheduleDot(
                            key: Key('schedule.dot.workout.$date'),
                            // Green on the accent fill would vanish.
                            color: isToday ? t.onAccent : t.accent,
                            filled: workout == DotState.done,
                          ),
                        if (workout != DotState.none && habits != DotState.none)
                          const SizedBox(width: 3),
                        if (habits != DotState.none)
                          ScheduleDot(
                            key: Key('schedule.dot.habits.$date'),
                            color: t.blue,
                            // Blue on the accent fill is close to unreadable;
                            // a small onAccent disc restores the contrast
                            // without changing the dot's own colour.
                            backing: isToday ? t.onAccent : null,
                            filled: habits == DotState.done,
                          ),
                      ],
                    ),
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

/// Filled for done, a ring for planned or due.
///
/// [backing] draws a small disc behind the dot, 2px larger on every side, in
/// that colour -- for a dot whose own colour would otherwise sit too close
/// to the colour behind it.
class ScheduleDot extends StatelessWidget {
  const ScheduleDot({
    super.key,
    required this.color,
    required this.filled,
    this.backing,
  });

  final Color color;
  final bool filled;
  final Color? backing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.2),
      ),
    );
    final backingColor = backing;
    if (backingColor == null) return dot;
    return Container(
      width: 10,
      height: 10,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: backingColor),
      child: dot,
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    Widget entry(Color color, bool filled, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScheduleDot(color: color, filled: filled),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10.5, color: t.text2)),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        entry(t.accent, true, 'Workout done'),
        entry(t.accent, false, 'Workout planned'),
        entry(t.blue, true, 'Habits done'),
        entry(t.blue, false, 'Habits due'),
      ],
    );
  }
}
