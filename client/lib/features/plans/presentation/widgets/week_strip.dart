import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';

/// What one day of the strip has to say for itself.
///
/// An enum rather than a pair of booleans: `missed && trained` and
/// `missed && !chosen` are both nonsense, and a widget taking three flags
/// cannot refuse them.
enum DayMark {
  /// A session was completed on this date.
  trained,

  /// The user chose this day, it has passed, and nothing was logged.
  missed,

  /// A training day that has not happened yet -- or, when no days have been
  /// chosen at all, any day, because any day is then one you might train.
  planned,

  /// Not a training day.
  none,
}

/// One cell. Public so tests can read its flags rather than infer them from
/// colours, which would break the moment the palette moves.
class WeekDayCell extends StatelessWidget {
  const WeekDayCell({
    super.key,
    required this.label,
    required this.mark,
    required this.isToday,
  });

  final String label;

  /// What this day is -- trained, missed, planned, or no mark at all. See
  /// [DayMark] and [WeekStrip] for why there is no "prescribed" state.
  final DayMark mark;

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
                  color: switch (mark) {
                    DayMark.trained => isToday ? t.onAccent : t.accent,
                    DayMark.missed => t.red,
                    DayMark.planned =>
                      isToday ? t.onAccent.withValues(alpha: 0.45) : t.line2,
                    DayMark.none => Colors.transparent,
                  },
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
/// user's chosen schedule.
///
/// It used to draw Mon/Wed/Fri from a hardcoded table keyed on
/// `days_per_week` -- a count, never a set of weekdays -- which made this the
/// only part of the app claiming the user had agreed to a schedule they never
/// chose. It read worst on the case that matters most: install the app on a
/// Tuesday and Monday was already marked, so the first thing a new user saw
/// was a day they had supposedly missed before they had signed up.
///
/// `trainingDays` now carries the schedule the user actually picked. Empty
/// means none chosen -- every day stays a possible training day, exactly what
/// this widget rendered before days could be chosen at all -- rather than a
/// default schedule nobody agreed to.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.daysPerWeek,
    required this.completedDates,
    required this.today,
    this.trainingDays = const [],
  });

  /// The plan's target, used only as the denominator of the tally. Nothing
  /// here maps it onto particular weekdays.
  final int daysPerWeek;

  /// `YYYY-MM-DD` for every completed session since Monday.
  final Set<String> completedDates;

  final DateTime today;

  /// Weekdays the user chose to train on, 1 = Monday .. 7 = Sunday.
  ///
  /// Three states, which is why this is nullable. `[]` means none chosen -- a
  /// real answer, and the one every user starts from. `null` means not known:
  /// the profile is still in flight, or its fetch failed. Flattening those
  /// two has a failed request assert "you chose no days" and hand the tally a
  /// denominator off the plan's stale label.
  ///
  /// Defaults to `[]` rather than null so a caller with no notion of chosen
  /// days at all reads as the state step 1 shipped.
  final List<int>? trainingDays;

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
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );

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
    final done = dates
        .where((date) => completedDates.contains(_key(date)))
        .length;

    final known = trainingDays != null;
    final chosen = trainingDays?.toSet() ?? const <int>{};
    // Compared by date, not by index, so "past" survives a week that spans a
    // month or year boundary the same way the keys already do.
    final todayKey = _key(DateTime(today.year, today.month, today.day));

    DayMark markFor(int weekday, DateTime date) {
      if (completedDates.contains(_key(date))) return DayMark.trained;
      // No choice made is not the same as choosing nothing to do: every day
      // stays a possible training day, which is what the strip rendered
      // before days could be chosen. Days that are not KNOWN read the same
      // way for the opposite reason -- with no schedule to report against,
      // the least this can claim is that any day might be one, and marking
      // nothing at all would be as much of an assertion as marking a
      // schedule.
      if (!known || chosen.isEmpty) return DayMark.planned;
      if (!chosen.contains(weekday)) return DayMark.none;
      // Strictly before today. Today is never missed -- the day is not over.
      return _key(date).compareTo(todayKey) < 0
          ? DayMark.missed
          : DayMark.planned;
    }

    final target = chosen.isNotEmpty ? chosen.length : daysPerWeek;
    // No target while the chosen days are unknown: the plan's count is the
    // right denominator only once "none chosen" has been confirmed. Falling
    // back to it before then makes the number move under the user when the
    // profile lands, and the bare count is already how this row reports a
    // week it cannot set a target for.
    final hasTarget = known && target >= _minTarget && target <= _maxTarget;

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
                    ? '$done of $target'
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
                mark: markFor(offset + 1, date),
                isToday: offset + 1 == today.weekday,
              ),
          ],
        ),
      ],
    );
  }
}
