import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';

/// One cell. Public so tests can read its flags rather than infer them from
/// colours, which would break the moment the palette moves.
class WeekDayCell extends StatelessWidget {
  const WeekDayCell({
    super.key,
    required this.label,
    required this.completed,
    required this.isToday,
  });

  final String label;

  /// Whether a session was completed on this date. The only thing a day is
  /// marked for -- see [WeekStrip] for why there is no "prescribed" state.
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
                // Keyed because the cell's own Container renders a
                // DecoratedBox too, and a test reading "the dot's colour" must
                // not be able to pick up the background by accident.
                key: const Key('day.dot'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Every day carries a dot, so the row keeps its rhythm and
                  // no day is singled out before it has been trained. Only
                  // two states exist: done, and not done yet.
                  color: completed
                      ? (isToday ? t.onAccent : t.accent)
                      : (isToday ? t.onAccent.withValues(alpha: 0.45) : t.line2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The week at a glance: what was trained, and how that stands against the
/// plan's target.
///
/// It deliberately does NOT say which weekdays to train on. Nothing in the
/// system knows: `workout_plans` stores `days_per_week` -- a count -- and
/// never which days, and `nextPlanDayNo` on the server advances the rotation
/// by completed sessions rather than by the calendar, so a missed Monday
/// costs a day rather than a session.
///
/// This widget used to draw Mon/Wed/Fri from a hardcoded table anyway, which
/// made it the only part of the app claiming the user had agreed to a
/// schedule. It read worst on the case that matters most: install the app on
/// a Tuesday and Monday was already marked, so the first thing a new user saw
/// was a day they had supposedly missed before they had signed up.
///
/// Letting users choose their own days is the real answer, and it needs a
/// schema change -- see `parkedquestion.md`. Until then the honest display is
/// what happened, counted against the number the plan actually holds.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.daysPerWeek,
    required this.completedDates,
    required this.today,
  });

  /// The plan's target, used only as the denominator of the tally. Nothing
  /// here maps it onto particular weekdays.
  final int daysPerWeek;

  /// `YYYY-MM-DD` for every completed session since Monday.
  final Set<String> completedDates;

  final DateTime today;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// The range `days_per_week` can meaningfully take. Outside it the column
  /// is not a target -- it is a bad row, and "1 of 0" renders that as a
  /// fraction instead of saying so.
  static const _minTarget = 1;
  static const _maxTarget = 7;

  static String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    // Calendar arithmetic, not absolute-time arithmetic: subtract(Duration)
    // subtracts exact hours, so on a week containing a DST change the whole
    // strip can slide a day. The DateTime constructor normalises out-of-range
    // day numbers over month and year ends and stays on the intended date.
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));

    // Same reason as `monday` above -- add(Duration) would re-open the DST
    // slide for the individual days.
    final dates = [
      for (var offset = 0; offset < 7; offset++)
        DateTime(monday.year, monday.month, monday.day + offset),
    ];
    // Counted from the days actually drawn, not from `completedDates.length`:
    // the set is scoped to this week by its provider today, and a tally that
    // trusted that would silently overcount the moment anything handed it a
    // wider range.
    final done = dates.where((date) => completedDates.contains(_key(date))).length;
    final hasTarget = daysPerWeek >= _minTarget && daysPerWeek <= _maxTarget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, right: 3, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(child: FsEyebrow('This week')),
              Text(
                hasTarget
                    ? '$done of $daysPerWeek'
                    : (done == 1 ? '1 session' : '$done sessions'),
                key: const Key('week.tally'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.accent,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final (offset, date) in dates.indexed)
              WeekDayCell(
                key: Key('day.${offset + 1}'),
                label: _labels[offset],
                completed: completedDates.contains(_key(date)),
                isToday: offset + 1 == today.weekday,
              ),
          ],
        ),
      ],
    );
  }
}
