import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/schedule/domain/calendar.dart';
import 'package:fitsync/features/schedule/domain/schedule_view.dart';
import 'package:fitsync/features/schedule/presentation/widgets/month_grid.dart';

const _sep = (year: 2026, month: 9);
const _t = FsTokens.light;

final _days = <String, CalendarDay>{
  // Past, done: a workout and a ticked habit.
  '2026-09-22': const CalendarDay(
    date: '2026-09-22',
    workout: CalendarWorkout(title: 'Upper/Lower', done: true),
    habits: [
      CalendarHabit(habitId: 1, title: 'Stretch', time: '06:30', done: true),
    ],
  ),
  // Past, nothing.
  '2026-09-23': const CalendarDay(
    date: '2026-09-23',
    workout: null,
    habits: [],
  ),
  // Today, partly done: the workout still to do, one of two habits ticked.
  '2026-09-24': const CalendarDay(
    date: '2026-09-24',
    workout: CalendarWorkout(title: 'Upper/Lower', done: false),
    habits: [
      CalendarHabit(habitId: 1, title: 'Stretch', time: '06:30', done: true),
      CalendarHabit(habitId: 2, title: 'Walk', time: null, done: false),
    ],
  ),
  // Future: a habit due, no workout.
  '2026-09-25': const CalendarDay(
    date: '2026-09-25',
    workout: null,
    habits: [CalendarHabit(habitId: 3, title: 'Read', time: null, done: false)],
  ),
};

Future<List<String>> _pump(
  WidgetTester tester, {
  Map<String, CalendarDay>? days,
  String? selected,
  bool tappable = true,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MonthGrid(
            month: _sep,
            dates: monthGridDates(_sep),
            today: '2026-09-24',
            days: days,
            selected: selected,
            onTapDay: tappable ? taps.add : null,
          ),
        ),
      ),
    ),
  );
  return taps;
}

ScheduleDayCell _cell(WidgetTester tester, String date) =>
    tester.widget<ScheduleDayCell>(find.byKey(Key('schedule.day.$date')));

ScheduleDot? _dot(WidgetTester tester, String kind, String date) {
  final finder = find.byKey(Key('schedule.dot.$kind.$date'));
  return finder.evaluate().isEmpty ? null : tester.widget<ScheduleDot>(finder);
}

void main() {
  testWidgets('42 cells from Monday 31 Aug, under Monday-first letters', (
    tester,
  ) async {
    await _pump(tester, days: _days);

    expect(find.byType(ScheduleDayCell), findsNWidgets(42));
    expect(find.byKey(const Key('schedule.day.2026-08-31')), findsOneWidget);
    expect(find.byKey(const Key('schedule.day.2026-10-11')), findsOneWidget);
    expect(find.byKey(const Key('schedule.day.2026-10-12')), findsNothing);

    final first = tester.getTopLeft(
      find.byKey(const Key('schedule.day.2026-08-31')),
    );
    final sunday = tester.getTopLeft(
      find.byKey(const Key('schedule.day.2026-09-06')),
    );
    final nextMonday = tester.getTopLeft(
      find.byKey(const Key('schedule.day.2026-09-07')),
    );
    expect(sunday.dy, first.dy, reason: 'Mon 31 Aug .. Sun 6 Sep share a row');
    expect(nextMonday.dy, greaterThan(first.dy));
    expect(nextMonday.dx, first.dx, reason: 'Mondays share a column');
  });

  testWidgets("neighbouring months' days are dimmed; today is filled", (
    tester,
  ) async {
    await _pump(tester, days: _days);

    expect(_cell(tester, '2026-08-31').inMonth, isFalse);
    expect(_cell(tester, '2026-09-01').inMonth, isTrue);
    expect(_cell(tester, '2026-10-01').inMonth, isFalse);
    double opacity(String date) => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byKey(Key('schedule.day.$date')),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;
    expect(opacity('2026-08-31'), lessThan(1));
    expect(opacity('2026-09-01'), 1);

    Color? fill(String date) => tester
        .widget<Material>(
          find.descendant(
            of: find.byKey(Key('schedule.day.$date')),
            matching: find.byType(Material),
          ),
        )
        .color;
    expect(_cell(tester, '2026-09-24').isToday, isTrue);
    expect(fill('2026-09-24'), _t.accent);
    expect(fill('2026-09-23'), Colors.transparent);
  });

  testWidgets('dots: done filled, planned a ring, nothing none', (
    tester,
  ) async {
    await _pump(tester, days: _days);

    // Past, done.
    expect(_dot(tester, 'workout', '2026-09-22')!.filled, isTrue);
    expect(_dot(tester, 'habits', '2026-09-22')!.filled, isTrue);
    expect(_dot(tester, 'habits', '2026-09-22')!.color, _t.blue);
    // Past, nothing.
    expect(_dot(tester, 'workout', '2026-09-23'), isNull);
    expect(_dot(tester, 'habits', '2026-09-23'), isNull);
    // Today, partly done.
    expect(_dot(tester, 'workout', '2026-09-24')!.filled, isFalse);
    expect(_dot(tester, 'habits', '2026-09-24')!.filled, isTrue);
    // Future, a habit due.
    expect(_dot(tester, 'workout', '2026-09-25'), isNull);
    expect(_dot(tester, 'habits', '2026-09-25')!.filled, isFalse);
    expect(_dot(tester, 'workout', '2026-09-22')!.color, _t.accent);
  });

  testWidgets('no dots while nothing has loaded, and taps do nothing', (
    tester,
  ) async {
    final taps = await _pump(tester, days: null, tappable: false);

    expect(
      find.byType(ScheduleDot).evaluate().length,
      4,
      reason: 'legend only',
    );
    await tester.tap(find.byKey(const Key('schedule.day.2026-09-22')));
    expect(taps, isEmpty);
  });

  testWidgets('a tap reports the date; the selected day is marked', (
    tester,
  ) async {
    final taps = await _pump(tester, days: _days, selected: '2026-09-22');

    await tester.tap(find.byKey(const Key('schedule.day.2026-09-25')));
    expect(taps, ['2026-09-25']);
    expect(_cell(tester, '2026-09-22').selected, isTrue);
    expect(_cell(tester, '2026-09-25').selected, isFalse);
  });

  testWidgets('a legend explains the dots', (tester) async {
    await _pump(tester, days: _days);

    for (final label in [
      'Workout done',
      'Workout planned',
      'Habits done',
      'Habits due',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
