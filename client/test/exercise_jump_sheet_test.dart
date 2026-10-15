// The jump sheet on a small phone. A plan of six or more exercises used to
// run off the bottom of a sheet capped at 9/16 of the screen, with no way to
// scroll to the rest. The list now scrolls inside a sheet that fits it, up to
// most of the screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_jump_sheet.dart';

List<PlanExercise> _plan(int count) => [
  for (var i = 0; i < count; i++)
    PlanExercise(
      planExerciseId: 600 + i,
      exerciseId: 100 + i,
      name: 'Exercise ${i + 1}',
      muscleGroup: 'quadriceps',
      orderNo: i + 1,
      targetSets: 3,
      targetReps: '8-12',
    ),
];

/// Opens the sheet the way the logger does, on a 360 x 640 phone. Whatever the
/// sheet resolves to -- an index, or null when dismissed -- lands in the list
/// returned.
Future<List<int?>> _open(
  WidgetTester tester, {
  required int count,
  int current = 0,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final chosen = <int?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showExerciseJumpSheet(
                context,
                exercises: _plan(count),
                session: null,
                currentIndex: current,
              ).then(chosen.add),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return chosen;
}

final _sheet = find.byType(ExerciseJumpSheet);

Finder get _list =>
    find.descendant(of: _sheet, matching: find.byType(Scrollable)).first;

void main() {
  // Every row is built up front, so only a hit-testable finder makes
  // scrollUntilVisible drag the list the way a finger does -- rather than
  // jump it there programmatically, which works on a list nobody can scroll.
  testWidgets(
    'a long plan on a small phone: nothing overflows, and the last exercise '
    'can be dragged into view and chosen',
    (tester) async {
      final chosen = await _open(tester, count: 20);

      expect(tester.takeException(), isNull);
      final last = find.byKey(const Key('jump.119'));
      await tester.scrollUntilVisible(
        last.hitTestable(),
        100,
        scrollable: _list,
      );
      await tester.tap(last);
      await tester.pumpAndSettle();

      expect(chosen, [19]);
    },
  );

  // Sheet over a workout, not a new screen: some of the workout stays in
  // view, and tapping it is the way out.
  testWidgets('a long list still leaves the workout showing above the sheet, '
      'and a tap there closes it', (tester) async {
    final chosen = await _open(tester, count: 20);

    // Most of the screen, not the old half: the list gets the room there is.
    expect(tester.getSize(_sheet).height, greaterThan(640 * 0.75));
    expect(tester.getTopLeft(_sheet).dy, greaterThan(0));
    await tester.tapAt(const Offset(180, 10));
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
    expect(chosen, [null]);
  });

  // On a list that scrolls, a drag on the rows scrolls them; the handle and
  // the title are where a swipe down closes the sheet.
  testWidgets('a swipe down on the title closes a long list', (tester) async {
    final chosen = await _open(tester, count: 20);

    await tester.drag(find.text('Jump to an exercise'), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
    expect(chosen, [null]);
  });

  testWidgets('a short list keeps the sheet short', (tester) async {
    await _open(tester, count: 2);

    expect(tester.getSize(_sheet).height, lessThan(640 / 2));
  });

  testWidgets('a long list opens with the exercise you are on in view', (
    tester,
  ) async {
    await _open(tester, count: 20, current: 17);

    final view = tester.getRect(_list);
    final row = tester.getRect(find.byKey(const Key('jump.117')));
    expect(row.top, greaterThanOrEqualTo(view.top));
    expect(row.bottom, lessThanOrEqualTo(view.bottom));
  });
}
