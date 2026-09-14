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

/// A two-day rotation whose days hold different numbers of exercises, so a
/// count of the whole plan cannot pass for a count of today's day.
const _rotationPlan = WorkoutPlan(
  planId: 43,
  name: 'Upper / Lower — Build Muscle',
  splitStyle: 'upper_lower',
  daysPerWeek: 4,
  sessionLengthMin: 45,
  weekNo: 1,
  days: [
    PlanDay(dayNo: 1, name: 'Upper'),
    PlanDay(dayNo: 2, name: 'Lower'),
  ],
  exercises: [
    PlanExercise(
      planExerciseId: 611, exerciseId: 111, name: 'Bench press',
      muscleGroup: 'pectorals', orderNo: 1, targetSets: 3, targetReps: '8-12',
      dayNo: 1,
    ),
    PlanExercise(
      planExerciseId: 612, exerciseId: 112, name: 'Back squat',
      muscleGroup: 'quads', orderNo: 1, targetSets: 3, targetReps: '8-12',
      dayNo: 2,
    ),
    PlanExercise(
      planExerciseId: 613, exerciseId: 113, name: 'Leg curl',
      muscleGroup: 'hamstrings', orderNo: 2, targetSets: 3, targetReps: '8-12',
      dayNo: 2,
    ),
  ],
);

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: child),
    );

void main() {
  DayMark markFor(WidgetTester tester, int weekday) =>
      tester.widget<WeekDayCell>(find.byKey(Key('day.$weekday'))).mark;

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

  testWidgets('a day the user trained fills, whatever day of the week it is',
      (tester) async {
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      // Sunday of that week.
      completedDates: const {'2026-09-13'},
      today: DateTime(2026, 9, 8),
    )));

    expect(tester.widget<WeekDayCell>(find.byKey(const Key('day.7'))).mark,
        DayMark.trained);
    expect(tester.widget<WeekDayCell>(find.byKey(const Key('day.1'))).mark,
        isNot(DayMark.trained));
  });

  testWidgets('the strip singles out no weekday, whatever the day count',
      (tester) async {
    // The property the prescribed-weekday table broke. `workout_plans` stores
    // how many days, never which ones, and the rotation advances on completed
    // sessions rather than on the calendar -- so nothing in the system knows
    // that Monday was supposed to be a training day. Drawing Mon/Wed/Fri from
    // a hardcoded table told users they had agreed to a schedule they never
    // chose, and told anyone who installed on a Tuesday they had already
    // missed one.
    //
    // Asserted by comparing two different day counts rather than against a
    // fixed set: identical output for 3 and for 5 is what "the count no longer
    // decides which weekdays are marked" means.
    // Read as painted colour, not as a flag: a `prescribed` field the strip
    // still honoured would leave the flags identical while the dots differed,
    // which is precisely the state this test exists to rule out.
    List<Color?> dots() => [
          for (var weekday = 1; weekday <= 7; weekday++)
            (tester
                    .widget<DecoratedBox>(find.descendant(
                      of: find.byKey(Key('day.$weekday')),
                      matching: find.byKey(const Key('day.dot')),
                    ))
                    .decoration as BoxDecoration)
                .color,
        ];

    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      completedDates: const {'2026-09-09'},
      today: DateTime(2026, 9, 8),
    )));
    final three = dots();

    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 5,
      completedDates: const {'2026-09-09'},
      today: DateTime(2026, 9, 8),
    )));

    expect(dots(), three,
        reason: 'the day count must not change which weekdays are marked');
    // Non-vacuous: the assertion above would also hold if every dot were
    // identical. Wednesday was trained and Thursday was not, so those two must
    // still differ -- today's cell is excluded because it is legitimately
    // styled apart, which is what 'today is marked' covers.
    expect(three[DateTime.wednesday - 1], isNot(three[DateTime.thursday - 1]),
        reason: 'a trained day must still be distinguishable');
  });

  testWidgets('a fresh install mid-week accuses the user of nothing',
      (tester) async {
    // Tuesday, nothing trained, because the app was installed this morning.
    // Under the prescribed table this rendered a marked Monday the user had
    // no way to have honoured.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      completedDates: const {},
      today: DateTime(2026, 9, 8),
    )));

    for (var weekday = 1; weekday <= 7; weekday++) {
      expect(
        tester.widget<WeekDayCell>(find.byKey(Key('day.$weekday'))).mark,
        isNot(DayMark.trained),
        reason: 'day $weekday cannot be filled before anything was trained',
      );
    }
    expect(find.text('0 of 3'), findsOneWidget);
  });

  testWidgets('the strip counts the week against the plan target',
      (tester) async {
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      completedDates: const {'2026-09-07', '2026-09-09'},
      today: DateTime(2026, 9, 8),
    )));

    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('the count is of days shown, not of dates handed in',
      (tester) async {
    // A date outside the rendered week must not inflate the tally. Counting
    // the set's length would report 2 for a week with one session in it.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      completedDates: const {'2026-09-09', '2026-08-31'},
      today: DateTime(2026, 9, 8),
    )));

    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('training more than the target reports what actually happened',
      (tester) async {
    // "3 of 3" would be a nicer number and a false one. The target is what
    // the plan asks for, not a ceiling on what gets counted.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 2,
      completedDates: const {'2026-09-07', '2026-09-08', '2026-09-09'},
      today: DateTime(2026, 9, 8),
    )));

    expect(find.text('3 of 2'), findsOneWidget);
  });

  testWidgets('a plan with no usable day count states the tally alone',
      (tester) async {
    // days_per_week is an INT with no CHECK, and WorkoutPlan.fromJson defaults
    // it to 0 when the key is absent. "1 of 0" is not a target, it is a bug
    // rendered as a fraction.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 0,
      completedDates: const {'2026-09-09'},
      today: DateTime(2026, 9, 8),
    )));

    expect(find.text('1 session'), findsOneWidget);
    expect(find.textContaining(' of '), findsNothing);
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
    expect(monday.mark, DayMark.trained);

    // Neighbouring days must NOT also read as completed — otherwise a broken
    // key that happened to match everything would pass the assertion above
    // for the wrong reason.
    final wednesday = tester.widget<WeekDayCell>(find.byKey(const Key('day.3')));
    expect(wednesday.mark, isNot(DayMark.trained));
    final today = tester.widget<WeekDayCell>(find.byKey(const Key('day.4')));
    expect(today.mark, isNot(DayMark.trained));
  });

  testWidgets('a week spanning a year boundary walks back into the prior year',
      (tester) async {
    // Friday 2027-01-01: its Monday is 2026-12-28. The Monday is now computed
    // as DateTime(year, month, day - (weekday - 1)) -- calendar arithmetic
    // rather than subtract(Duration), which slides a day across a DST change.
    // Day 1 - 4 is negative, so this also proves the constructor's
    // normalisation carries back over both the month and the year.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      completedDates: const {'2026-12-28', '2027-01-01'},
      today: DateTime(2027, 1, 1),
    )));

    expect(tester.widget<WeekDayCell>(find.byKey(const Key('day.1'))).mark,
        DayMark.trained);
    expect(tester.widget<WeekDayCell>(find.byKey(const Key('day.5'))).mark,
        DayMark.trained);
    expect(tester.widget<WeekDayCell>(find.byKey(const Key('day.4'))).mark,
        isNot(DayMark.trained));
  });

  testWidgets('a chosen day that has passed untrained is missed',
      (tester) async {
    // Thursday. Monday and Wednesday were chosen and not trained.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      trainingDays: const [1, 3, 5],
      completedDates: const {},
      today: DateTime(2026, 9, 10),
    )));

    expect(markFor(tester, DateTime.monday), DayMark.missed);
    expect(markFor(tester, DateTime.wednesday), DayMark.missed);
  });

  testWidgets('today is never missed, however late in the day it is',
      (tester) async {
    // Wednesday, chosen, not yet trained. The day is not over.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      trainingDays: const [1, 3, 5],
      completedDates: const {},
      today: DateTime(2026, 9, 9),
    )));

    expect(markFor(tester, DateTime.wednesday), DayMark.planned);
  });

  testWidgets('a chosen day still to come is planned, not missed',
      (tester) async {
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      trainingDays: const [1, 3, 5],
      completedDates: const {},
      today: DateTime(2026, 9, 9),
    )));

    expect(markFor(tester, DateTime.friday), DayMark.planned);
  });

  testWidgets('a day nobody chose carries no mark at all', (tester) async {
    // The schedule has to be visible BEFORE any of it is missed, so a chosen
    // future day and an unchosen day cannot render the same.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      trainingDays: const [1, 3, 5],
      completedDates: const {},
      today: DateTime(2026, 9, 9),
    )));

    expect(markFor(tester, DateTime.tuesday), DayMark.none);
    expect(markFor(tester, DateTime.sunday), DayMark.none);
  });

  testWidgets('a trained day fills even on a weekday nobody chose',
      (tester) async {
    // The strip reports what happened, not only what was asked for.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      trainingDays: const [1, 3, 5],
      completedDates: const {'2026-09-08'},
      today: DateTime(2026, 9, 10),
    )));

    expect(markFor(tester, DateTime.tuesday), DayMark.trained);
  });

  testWidgets('with nothing chosen every day is planned, as before',
      (tester) async {
    // Step 1's behaviour, unchanged: every day is one you might train, so the
    // row keeps its rhythm and no day is singled out.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 3,
      trainingDays: const [],
      completedDates: const {},
      today: DateTime(2026, 9, 10),
    )));

    for (var weekday = 1; weekday <= 7; weekday++) {
      expect(markFor(tester, weekday), DayMark.planned,
          reason: 'day $weekday must not be missed when no day was chosen');
    }
  });

  testWidgets('the tally counts against the chosen days, not the plan',
      (tester) async {
    // The user just said three days. The plan's stored label is a stale four
    // until the next regeneration, and the number on screen must follow what
    // the user said.
    await tester.pumpWidget(_host(WeekStrip(
      daysPerWeek: 4,
      trainingDays: const [1, 3, 5],
      completedDates: const {'2026-09-07'},
      today: DateTime(2026, 9, 10),
    )));

    expect(find.text('1 of 3'), findsOneWidget);
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

  testWidgets("the card counts today's day, not the whole rotation",
      (tester) async {
    // The card sat directly above the Plan tab's exercise list, which shows
    // one day: "3 exercises" over a list of one is the card disagreeing with
    // the screen it is on.
    await tester.pumpWidget(_host(SessionCard(
      plan: _rotationPlan, hasActiveSession: false, onStart: () {},
    )));

    expect(find.textContaining('1 exercise'), findsOneWidget);
    expect(find.textContaining('3 exercises'), findsNothing);

    // And it is the day it was handed, not day 1 for everyone: Lower holds
    // two of the three. Without this, a filter hardcoded to day 1 would pass
    // the assertion above just as well as a correct one.
    await tester.pumpWidget(_host(SessionCard(
      plan: _rotationPlan, hasActiveSession: false, dayNo: 2, onStart: () {},
    )));

    expect(find.textContaining('2 exercises'), findsOneWidget);
  });
}
