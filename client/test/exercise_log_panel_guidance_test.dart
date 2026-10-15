// Logging help: the empty reps box shows the target range. Its own file:
// exercise_log_panel_test.dart is the extraction's safety net and stays
// unmodified.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_log_panel.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';

PlanExercise _exercise({String reps = '8-12'}) => PlanExercise(
  planExerciseId: 601,
  exerciseId: 101,
  name: 'Goblet squat',
  muscleGroup: 'quadriceps',
  orderNo: 1,
  targetSets: 3,
  targetReps: reps,
  equipment: 'dumbbell',
);

ActiveSession _session() => const ActiveSession(
  sessionId: 7,
  status: 'in_progress',
  sessionDate: '2026-09-08',
  sets: [],
);

Future<void> _pump(WidgetTester tester, {PlanExercise? exercise}) async {
  final drafts = SetDrafts();
  addTearDown(drafts.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExerciseLogPanel(
            exercise: exercise ?? _exercise(),
            session: _session(),
            drafts: drafts,
            onUndoSet: (_) async {},
          ),
        ),
      ),
    ),
  );
}

String? _hintOf(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).decoration?.hintText;

void main() {
  testWidgets('the empty reps box shows the target range', (tester) async {
    await _pump(tester);

    expect(_hintOf(tester, 'set.1.reps'), '8-12');
  });

  // The range is data, so it is drawn in the readable grey, not the faint
  // caption colour that fails contrast.
  testWidgets('the reps hint is readable grey', (tester) async {
    await _pump(tester);

    final style = tester
        .widget<TextField>(find.byKey(const Key('set.1.reps')))
        .decoration
        ?.hintStyle;
    expect(style?.color, FsTokens.light.text2);
  });

  // With the hint now a number, a screen reader still has to hear which box
  // this is, typed into or not.
  testWidgets('the boxes are announced as Weight and Reps', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    // The field's own node sits on its EditableText; asking from the
    // TextField itself walks up to the card instead.
    String labelOf(String key) => tester
        .getSemantics(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(EditableText),
          ),
        )
        .label;
    expect(labelOf('set.1.reps'), contains('Reps'));
    expect(labelOf('set.1.weight'), contains('Weight'));
    handle.dispose();
  });

  testWidgets('with no target range, the reps box still says reps', (
    tester,
  ) async {
    await _pump(tester, exercise: _exercise(reps: ''));

    expect(_hintOf(tester, 'set.1.reps'), 'reps');
  });

  testWidgets('fits a 320 dp phone at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester);

    expect(tester.takeException(), isNull);
  });
}
