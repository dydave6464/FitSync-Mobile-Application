import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/sessions/presentation/widgets/logger_action.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('names the set it is about to log', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    await tester.pumpWidget(_host(LoggerAction(
      activeSetNumber: 3,
      isLastExercise: false,
      drafts: drafts,
      unit: WeightUnit.kg,
      onCompleteSet: (_, _, _) async {},
      onNextExercise: () {},
      onFinish: () {},
    )));

    expect(find.text('Complete set 3'), findsOneWidget);
  });

  testWidgets('reports the active row\'s typed weight and reps', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    drafts.weight(2).text = '25';
    drafts.reps(2).text = '8';

    int? gotSet;
    double? gotWeight;
    int? gotReps;

    await tester.pumpWidget(_host(LoggerAction(
      activeSetNumber: 2,
      isLastExercise: false,
      drafts: drafts,
      unit: WeightUnit.kg,
      onCompleteSet: (setNumber, weightKg, reps) async {
        gotSet = setNumber;
        gotWeight = weightKg;
        gotReps = reps;
      },
      onNextExercise: () {},
      onFinish: () {},
    )));

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(gotSet, 2);
    expect(gotWeight, 25);
    expect(gotReps, 8);
  });

  // The storage contract, now that the button is what reads the field:
  // whatever unit is on screen, the server is handed kilograms.
  testWidgets('a weight typed in pounds is reported in kilograms',
      (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    drafts.weight(1).text = '100';

    double? sentKg;
    await tester.pumpWidget(_host(LoggerAction(
      activeSetNumber: 1,
      isLastExercise: false,
      drafts: drafts,
      unit: WeightUnit.lb,
      onCompleteSet: (_, weightKg, _) async => sentKg = weightKg,
      onNextExercise: () {},
      onFinish: () {},
    )));

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(sentKg, closeTo(45.359237, 1e-9));
  });

  testWidgets('an empty weight is sent as null, not zero', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    drafts.reps(1).text = '10';

    var called = false;
    double? sentKg = 99;
    await tester.pumpWidget(_host(LoggerAction(
      activeSetNumber: 1,
      isLastExercise: false,
      drafts: drafts,
      unit: WeightUnit.kg,
      onCompleteSet: (_, weightKg, _) async {
        called = true;
        sentKg = weightKg;
      },
      onNextExercise: () {},
      onFinish: () {},
    )));

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(sentKg, isNull);
  });

  testWidgets('a finished exercise offers the next one', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    var advanced = false;
    await tester.pumpWidget(_host(LoggerAction(
      activeSetNumber: null,
      isLastExercise: false,
      drafts: drafts,
      unit: WeightUnit.kg,
      onCompleteSet: (_, _, _) async {},
      onNextExercise: () => advanced = true,
      onFinish: () {},
    )));

    expect(find.text('Next exercise'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(advanced, isTrue);
  });

  testWidgets('the last finished exercise offers to finish the session',
      (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    var finished = false;
    await tester.pumpWidget(_host(LoggerAction(
      activeSetNumber: null,
      isLastExercise: true,
      drafts: drafts,
      unit: WeightUnit.kg,
      onCompleteSet: (_, _, _) async {},
      onNextExercise: () {},
      onFinish: () => finished = true,
    )));

    expect(find.text('Finish session'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
  });

  // The retry moved here with the action. A failed write must not tick the
  // set, and must leave a way to try again.
  testWidgets('a failed write shows a retry and logs nothing', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    var attempts = 0;
    await tester.pumpWidget(_host(LoggerAction(
      activeSetNumber: 1,
      isLastExercise: false,
      drafts: drafts,
      unit: WeightUnit.kg,
      onCompleteSet: (_, _, _) async {
        attempts++;
        throw Exception('network');
      },
      onNextExercise: () {},
      onFinish: () {},
    )));

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.text('Retry set 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
