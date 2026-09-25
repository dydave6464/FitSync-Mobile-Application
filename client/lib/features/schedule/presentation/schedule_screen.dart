import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/manila_day.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../profile/presentation/providers.dart' show profileProvider;
import '../../reminders/presentation/providers.dart'
    show reminderSettingsProvider;
import '../domain/calendar.dart';
import '../domain/schedule_view.dart';
import 'providers.dart';
import 'widgets/month_grid.dart';

/// Past days show what was done, future days what is planned: a month grid,
/// then the coming week's items -- or, after a tap, one day's.
///
/// The grid and the list are separate requests, so one failing never hides
/// the other.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key, this.now = DateTime.now});

  /// The clock, so tests can fix "today". Only a first guess: once the
  /// server answers, its today wins.
  final DateTime Function() now;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// Set by prev/next; until then the grid follows today's month.
  YearMonth? _pinnedMonth;

  /// The tapped day, or null for Upcoming.
  String? _selected;

  void _shiftMonth(YearMonth shown, int delta) => setState(() {
    _pinnedMonth = shiftMonth(shown, delta);
    _selected = null;
  });

  void _tapDay(String date) =>
      setState(() => _selected = _selected == date ? null : date);

  /// The master switch and the reminder settings, or null until both load.
  ReminderContext? _reminders() {
    final profile = ref.watch(profileProvider);
    final settings = ref.watch(reminderSettingsProvider);
    if (!profile.hasValue || !settings.hasValue) return null;
    return (
      masterOn: profile.value!.notificationsEnabled,
      settings: settings.value!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final deviceToday = manilaDayOf(widget.now());
    final CalendarSpan weekSpan = (
      from: deviceToday,
      to: addDays(deviceToday, 6),
    );
    final week = ref.watch(calendarProvider(weekSpan));
    final today = week.hasValue && !week.hasError
        ? week.value!.today
        : deviceToday;

    final month = _pinnedMonth ?? monthOf(today);
    final dates = monthGridDates(month);
    final CalendarSpan gridSpan = (from: dates.first, to: dates.last);
    final grid = ref.watch(calendarProvider(gridSpan));
    final loaded = grid.hasError ? null : grid.value;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Schedule')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          FsCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatMonthTitle(month),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('schedule.prev'),
                      tooltip: 'Previous month',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _shiftMonth(month, -1),
                    ),
                    IconButton(
                      key: const Key('schedule.next'),
                      tooltip: 'Next month',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _shiftMonth(month, 1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MonthGrid(
                  month: month,
                  dates: dates,
                  today: loaded?.today ?? today,
                  days: loaded == null
                      ? null
                      : {for (final d in loaded.days) d.date: d},
                  selected: _selected,
                  onTapDay: loaded == null ? null : _tapDay,
                ),
                if (grid.hasError)
                  _SectionError(
                    message: "Couldn't load this month",
                    buttonKey: const Key('schedule.grid.retry'),
                    onRetry: () => ref.invalidate(calendarProvider(gridSpan)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (_selected == null)
            ..._upcoming(week, weekSpan, _reminders())
          else
            ..._day(_selected!, loaded),
        ],
      ),
    );
  }

  List<Widget> _upcoming(
    AsyncValue<CalendarRange> week,
    CalendarSpan span,
    ReminderContext? reminders,
  ) => [
    Row(
      children: [
        const Expanded(child: _SectionTitle('Upcoming')),
        if (reminders != null)
          FsTag(remindersOn(reminders) ? 'Reminders on' : 'Reminders off'),
      ],
    ),
    const SizedBox(height: 10),
    week.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _SectionError(
        message: "Couldn't load what's coming up",
        buttonKey: const Key('schedule.list.retry'),
        onRetry: () => ref.invalidate(calendarProvider(span)),
      ),
      data: (range) {
        final items = upcomingItems(range);
        if (items.isEmpty) return const _Empty('Nothing coming up this week.');
        return Column(
          children: [
            for (final (i, item) in items.indexed)
              _ItemRow(
                key: Key('schedule.item.$i'),
                item: item,
                line1: upcomingLine(item, range.today),
                line2: reminders == null ? null : reminderLine(item, reminders),
              ),
          ],
        );
      },
    ),
  ];

  List<Widget> _day(String date, CalendarRange? grid) {
    CalendarDay? day;
    for (final d in grid?.days ?? const <CalendarDay>[]) {
      if (d.date == date) day = d;
    }
    final past = grid != null && date.compareTo(grid.today) < 0;
    final items = day == null
        ? const <ScheduleItem>[]
        : dayItems(day).where((i) => !past || i.done).toList();
    return [
      Row(
        children: [
          Expanded(child: _SectionTitle(formatDayLabel(date))),
          TextButton(
            key: const Key('schedule.upcoming'),
            onPressed: () => setState(() => _selected = null),
            child: const Text('Back to upcoming'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (items.isEmpty)
        _Empty(past ? 'Nothing logged this day.' : 'Nothing planned.')
      else
        for (final (i, item) in items.indexed)
          _ItemRow(
            key: Key('schedule.item.$i'),
            item: item,
            line1: itemLine(item),
            showDone: true,
          ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: context.fs.text,
    ),
  );
}

/// A habit or the workout: a colour bar (green workout, blue habit), one or
/// two lines, and a check when [showDone] and it is done.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.line1,
    this.line2,
    this.showDone = false,
  });

  final ScheduleItem item;
  final String line1;
  final String? line2;
  final bool showDone;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final color = item.isWorkout ? t.accent : t.blue;
    final second = line2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FsCard(
        small: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  if (second != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      second,
                      style: TextStyle(fontSize: 11, color: t.text3),
                    ),
                  ],
                ],
              ),
            ),
            if (showDone && item.done)
              Icon(
                Icons.check_circle,
                size: 18,
                color: color,
                semanticLabel: 'Done',
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: context.fs.text2),
      ),
    ),
  );
}

class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.message,
    required this.buttonKey,
    required this.onRetry,
  });

  final String message;
  final Key buttonKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.fs.text2),
        ),
        const SizedBox(height: 8),
        FsButton(
          key: buttonKey,
          label: 'Retry',
          small: true,
          kind: FsButtonKind.secondary,
          onPressed: onRetry,
        ),
      ],
    ),
  );
}
