// Logging help from the UI/UX review: the empty reps box shows the target
// range, and an exercise with no history gets a one-line tip for choosing a
// starting weight. Its own file: exercise_log_panel_test.dart is the
// extraction's safety net and stays unmodified.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_log_panel.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';

const _tip = 'First time? Pick a weight you could lift 2–3 more times.';
final _tipFinder = find.byKey(const Key('logpanel.firstTime'));

PlanExercise _exercise({String reps = '8-12', String? equipment = 'dumbbell'}) =>
    PlanExercise(
      planExerciseId: 601,
      exerciseId: 101,
      name: 'Goblet squat',
      muscleGroup: 'quadriceps',
      orderNo: 1,
      targetSets: 3,
      targetReps: reps,
      equipment: equipment,
    );

ActiveSession _session() => const ActiveSession(
  sessionId: 7,
  status: 'in_progress',
  sessionDate: '2026-09-08',
  sets: [],
);

Future<void> _pump(
  WidgetTester tester, {
  PlanExercise? exercise,
  bool firstTime = false,
}) async {
  final drafts = SetDrafts();
  addTearDown(drafts.dispose);
  await tester.pumpWidget(MaterialApp(
    theme: fsLightTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ExerciseLogPanel(
          exercise: exercise ?? _exercise(),
          session: _session(),
          drafts: drafts,
          onUndoSet: (_) async {},
          firstTime: firstTime,
        ),
      ),
    ),
  ));
}

String? _hintOf(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).decoration?.hintText;

void main() {
  testWidgets('the empty reps box shows the target range', (tester) async {
    await _pump(tester);

    expect(_hintOf(tester, 'set.1.reps'), '8-12');
  });

  testWidgets('with no target range, the reps box still says reps', (tester) async {
    await _pump(tester, exercise: _exercise(reps: ''));

    expect(_hintOf(tester, 'set.1.reps'), 'reps');
  });

  testWidgets('a first-time weighted exercise gets the starting-weight tip', (tester) async {
    await _pump(tester, firstTime: true);

    expect(tester.widget<Text>(_tipFinder).data, _tip);
    expect(tester.widget<Text>(_tipFinder).style?.color, FsTokens.light.text2);
  });

  testWidgets('no tip once the exercise has history', (tester) async {
    await _pump(tester);

    expect(_tipFinder, findsNothing);
  });

  // A weight tip on push-ups would be advice for a field that is not there.
  testWidgets('no tip on a bodyweight exercise', (tester) async {
    await _pump(tester, exercise: _exercise(equipment: 'body weight'), firstTime: true);

    expect(_tipFinder, findsNothing);
  });

  testWidgets('fits a 320 dp phone at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, firstTime: true);

    expect(tester.takeException(), isNull);
    expect(_tipFinder, findsOneWidget);
  });
}
