import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/widgets/session_card.dart';
import 'package:fitsync/features/plans/presentation/widgets/week_strip.dart';

const _plan = WorkoutPlan(
  planId: 42,
  name: 'Week 1 — Full body',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [
    PlanExercise(
      planExerciseId: 601, exerciseId: 101, name: 'Goblet squat',
      muscleGroup: 'quadriceps', orderNo: 1, targetSets: 3, targetReps: '8-12',
    ),
  ],
);

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: child),
    );

void main() {
  group('trainingWeekdays', () {
    test('three days a week is Monday, Wednesday, Friday', () {
      expect(trainingWeekdays(3), [DateTime.monday, DateTime.wednesday, DateTime.friday]);
    });

    test('spaces rest days across the other counts', () {
      expect(trainingWeekdays(1), [DateTime.wednesday]);
      expect(trainingWeekdays(2), [DateTime.monday, DateTime.thursday]);
      expect(trainingWeekdays(4), [
        DateTime.monday, DateTime.tuesday, DateTime.thursday, DateTime.friday,
      ]);
      expect(trainingWeekdays(6), hasLength(6));
      expect(trainingWeekdays(7), hasLength(7));
    });

    test('a count outside 1-7 falls back to three days rather than throwing', () {
      // days_per_week is an INT with no CHECK, so a bad row must not crash
      // the tab that renders it.
      expect(trainingWeekdays(0), [DateTime.monday, DateTime.wednesday, DateTime.friday]);
      expect(trainingWeekdays(99), [DateTime.monday, DateTime.wednesday, DateTime.friday]);
    });
  });

  testWidgets('renders all seven days', (tester) async {
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      completedDates: const {},
      today: DateTime(2026, 9, 8), // a Tuesday
    )));

    for (var weekday = 1; weekday <= 7; weekday++) {
      expect(find.byKey(Key('day.$weekday')), findsOneWidget);
    }
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('a day the user actually trained fills, prescribed or not', (tester) async {
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      // Sunday of that week — not a prescribed day.
      completedDates: const {'2026-09-13'},
      today: DateTime(2026, 9, 8),
    )));

    final sunday = tester.widget<WeekDayCell>(find.byKey(const Key('day.7')));
    expect(sunday.completed, isTrue);
    expect(sunday.prescribed, isFalse);
  });

  testWidgets('today is marked', (tester) async {
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      completedDates: const {},
      today: DateTime(2026, 9, 8),
    )));

    final tuesday = tester.widget<WeekDayCell>(find.byKey(const Key('day.2')));
    expect(tuesday.isToday, isTrue);
  });

  testWidgets('a week spanning a month boundary keys days by their own month',
      (tester) async {
    // Thursday 2026-10-01: its Monday is 2026-09-28, in the PRIOR month.
    // A key built from today's month instead of each day's own month would
    // stamp that Monday as "2026-10-28" and silently unfill a dot the user
    // earned.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      completedDates: const {'2026-09-28'},
      today: DateTime(2026, 10, 1),
    )));

    final monday = tester.widget<WeekDayCell>(find.byKey(const Key('day.1')));
    expect(monday.completed, isTrue);

    // Neighbouring days must NOT also read as completed — otherwise a broken
    // key that happened to match everything would pass the assertion above
    // for the wrong reason.
    final wednesday = tester.widget<WeekDayCell>(find.byKey(const Key('day.3')));
    expect(wednesday.completed, isFalse);
    final today = tester.widget<WeekDayCell>(find.byKey(const Key('day.4')));
    expect(today.completed, isFalse);
  });

  testWidgets('the card offers Start with no session and Resume with one', (tester) async {
    await tester.pumpWidget(_host(SessionCard(
      plan: _plan, hasActiveSession: false, onStart: () {},
    )));
    expect(find.text('Start session'), findsOneWidget);

    await tester.pumpWidget(_host(SessionCard(
      plan: _plan, hasActiveSession: true, onStart: () {},
    )));
    expect(find.text('Resume session'), findsOneWidget);
  });

  testWidgets('the card states the plan facts honestly', (tester) async {
    await tester.pumpWidget(_host(SessionCard(
      plan: _plan, hasActiveSession: false, onStart: () {},
    )));

    expect(find.text('Week 1'), findsOneWidget);
    expect(find.text('Week 1 — Full body'), findsOneWidget);
    // The same session three times a week -- not three different days.
    expect(find.textContaining('3 days a week'), findsOneWidget);
    expect(find.textContaining('1 exercise'), findsOneWidget);
  });

  testWidgets('starting disables the button so it cannot be double-tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(SessionCard(
      plan: _plan, hasActiveSession: false, starting: true, onStart: () => taps++,
    )));

    await tester.tap(find.byKey(const Key('session.start')), warnIfMissed: false);
    expect(taps, 0);
  });
}
