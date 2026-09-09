// exercise_log_panel_test.dart is the extraction's safety net and must stay
// unmodified, so the new onOpenDemo affordance -- added after that file was
// written -- gets its own coverage here. Without this, onOpenDemo could be
// wired to nothing (or never rendered) and every test in the other file
// would still be green.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_log_panel.dart';

const _exercise = PlanExercise(
  planExerciseId: 601,
  exerciseId: 101,
  name: 'Goblet squat',
  muscleGroup: 'quadriceps',
  orderNo: 1,
  targetSets: 3,
  targetReps: '8-12',
);

ActiveSession _session() => const ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      sets: [],
    );

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

final _demoButton = find.byKey(const Key('logpanel.demo.101'));

void main() {
  testWidgets('tapping the demo affordance invokes onOpenDemo', (tester) async {
    var opened = false;

    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
      onOpenDemo: () => opened = true,
    )));

    await tester.tap(_demoButton);
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets('with no onOpenDemo, the affordance renders disabled rather than absent',
      (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    // If onOpenDemo were ever wired to a hardcoded no-op instead of passed
    // straight through, this would still find the icon but onPressed would
    // no longer be null.
    final tile = tester.widget<InkWell>(_demoButton);
    expect(tile.onTap, isNull);
  });
}
