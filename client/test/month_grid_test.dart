import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/schedule/domain/calendar.dart';
import 'package:fitsync/features/schedule/domain/schedule_view.dart';
import 'package:fitsync/features/schedule/presentation/widgets/month_grid.dart';

import 'helpers/a11y.dart' show contrast;

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
  bool dark = false,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? fsDarkTheme() : fsLightTheme(),
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

/// The colour a day's number is drawn in, after every [Opacity] above it
/// inside the cell: a faded cell fades the number with it.
Color _numberColor(WidgetTester tester, String date) {
  final cell = find.byKey(Key('schedule.day.$date'));
  final number = find.descendant(
    of: cell,
    matching: find.text('${int.parse(date.substring(8, 10))}'),
  );
  var alpha = 1.0;
  for (final opacity in tester.widgetList<Opacity>(
    find.ancestor(of: number, matching: find.byType(Opacity)),
  )) {
    alpha *= opacity.opacity;
  }
  final color = tester.widget<Text>(number).style!.color!;
  return color.withValues(alpha: color.a * alpha);
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
    // Dimmed by the number's colour, not by fading the cell (PT-27).
    expect(_numberColor(tester, '2026-08-31'), _t.text3);
    expect(_numberColor(tester, '2026-09-01'), _t.text);

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
    expect(_dot(tester, 'workout', '2026-09-22')!.color, _t.accentFill);
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

  testWidgets(
    "today's habits dot sits on an onAccent backing disc; other dots do not",
    (tester) async {
      await _pump(tester, days: _days);

      final todayHabits = _dot(tester, 'habits', '2026-09-24')!;
      expect(todayHabits.backing, _t.onAccent);
      expect(todayHabits.color, _t.blue);

      expect(_dot(tester, 'habits', '2026-09-22')!.backing, isNull);
      expect(_dot(tester, 'workout', '2026-09-24')!.backing, isNull);

      expect(_dot(tester, 'workout', '2026-09-24')!.color, _t.onAccent);
    },
  );

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

  for (final dark in [false, true]) {
    testWidgets('workout dots and their legend read at 3:1 '
        '(${dark ? 'dark' : 'light'}) (PT-13)', (tester) async {
      await _pump(tester, days: _days, dark: dark);
      final t = dark ? FsTokens.dark : FsTokens.light;

      final dots = [
        _dot(tester, 'workout', '2026-09-22')!,
        ...tester
            .widgetList<ScheduleDot>(
              find.descendant(
                of: find.byType(Wrap),
                matching: find.byType(ScheduleDot),
              ),
            )
            .take(2),
      ];
      expect(dots, hasLength(3));
      for (final dot in dots) {
        // The grid sits in a card; the page is behind the legend's edges.
        expect(contrast(dot.color, t.surface), greaterThanOrEqualTo(3));
        expect(contrast(dot.color, t.bg), greaterThanOrEqualTo(3));
      }
    });
  }

  for (final dark in [false, true]) {
    testWidgets("neighbouring months' day numbers read at 4.5:1 "
        '(${dark ? 'dark' : 'light'}) (PT-27)', (tester) async {
      // They stay tappable, so they have to stay readable: a whole cell at
      // 35% left the number at 2.25:1.
      await _pump(tester, days: _days, dark: dark);
      final t = dark ? FsTokens.dark : FsTokens.light;

      for (final date in ['2026-08-31', '2026-10-01']) {
        final color = _numberColor(tester, date);
        final shown = Color.alphaBlend(color, t.surface);
        expect(
          contrast(shown, t.surface),
          greaterThanOrEqualTo(4.5),
          reason: date,
        );
      }
    });
  }

  group('screen readers (PT-6)', () {
    testWidgets('a day says its date, today, and what its dots mean', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, days: _days, selected: '2026-09-22');

      expect(
        tester.getSemantics(find.byKey(const Key('schedule.day.2026-09-24'))),
        isSemantics(
          label: 'Thu 24 Sep, today, workout planned, habits done',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('schedule.day.2026-09-22'))),
        isSemantics(
          label: 'Tue 22 Sep, workout done, habits done',
          isSelected: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('schedule.day.2026-09-25'))),
        isSemantics(label: 'Fri 25 Sep, habits due'),
      );
      // The bare number is folded into the label, not read again.
      expect(find.bySemanticsLabel('24'), findsNothing);
      handle.dispose();
    });

    testWidgets('a day that cannot be tapped yet is not a button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, days: null, tappable: false);

      final node = tester.getSemantics(
        find.byKey(const Key('schedule.day.2026-09-24')),
      );
      expect(node.label, 'Thu 24 Sep, today');
      expect(node.getSemanticsData().flagsCollection.isButton, isFalse);
      handle.dispose();
    });
  });
}
