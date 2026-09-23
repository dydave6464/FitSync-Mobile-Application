import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart' show FsTag;
import 'package:fitsync/features/home/presentation/widgets/routine_card.dart';
import 'package:fitsync/features/routine/domain/routine.dart';

Habit _habit(int id, String title, {bool done = false, String? time}) => Habit(
  habitId: id,
  title: title,
  time: time,
  durationMin: null,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  done: done,
);

RoutineDay _day(List<Habit> habits, {RoutineWorkout? workout}) =>
    RoutineDay(date: '2026-09-24', habits: habits, workout: workout);

Future<List<String>> _pump(WidgetTester tester, RoutineDay day) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: RoutineCard(day: day, onTap: () => taps.add('tap')),
      ),
    ),
  );
  return taps;
}

void main() {
  testWidgets('several items show the heading, tag, first three titles and a '
      '"more" label', (tester) async {
    final day = _day([
      _habit(1, 'Habit 1', time: '06:00'),
      _habit(2, 'Habit 2', time: '07:00', done: true),
      _habit(3, 'Habit 3', time: '08:00'),
      _habit(4, 'Habit 4', time: '09:00', done: true),
      _habit(5, 'Habit 5', time: '10:00'),
    ]);
    await _pump(tester, day);

    expect(find.text("Today's routine"), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    // Only the first three, in screen order.
    expect(find.text('Habit 1'), findsOneWidget);
    expect(find.text('Habit 2'), findsOneWidget);
    expect(find.text('Habit 3'), findsOneWidget);
    expect(find.text('Habit 4'), findsNothing);
    expect(find.text('Habit 5'), findsNothing);
    expect(find.byKey(const Key('home.routine.more')), findsOneWidget);
    expect(find.text('+2 more'), findsOneWidget);
  });

  testWidgets('three or fewer entries show no "more" label', (tester) async {
    final day = _day([
      _habit(1, 'Habit 1', time: '06:00'),
      _habit(2, 'Habit 2', time: '07:00'),
      _habit(3, 'Habit 3', time: '08:00'),
    ]);
    await _pump(tester, day);

    expect(find.byKey(const Key('home.routine.more')), findsNothing);
  });

  testWidgets('a ticked item shows its title struck through', (tester) async {
    final day = _day([
      _habit(1, 'Done habit', time: '06:00', done: true),
      _habit(2, 'Open habit', time: '07:00'),
    ]);
    await _pump(tester, day);

    final doneText = tester.widget<Text>(find.text('Done habit'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
    final openText = tester.widget<Text>(find.text('Open habit'));
    expect(openText.style?.decoration, TextDecoration.none);
  });

  testWidgets('no habits and no workout shows the build-routine prompt', (
    tester,
  ) async {
    final day = _day(const []);
    await _pump(tester, day);

    expect(find.text("Nothing on today's routine ›"), findsOneWidget);
    expect(find.byType(FsTag), findsNothing);
  });

  testWidgets('tapping the card, including its tick boxes, calls onTap', (
    tester,
  ) async {
    final day = _day([_habit(1, 'Habit 1', time: '06:00', done: true)]);
    final taps = await _pump(tester, day);

    await tester.tap(find.byKey(const Key('home.routine')));
    expect(taps, ['tap']);

    taps.clear();
    // The mini tick box carries no gesture handling of its own; tapping it
    // must still land on the card-wide target rather than doing nothing.
    await tester.tap(find.byIcon(Icons.check));
    expect(taps, ['tap']);
  });
}
