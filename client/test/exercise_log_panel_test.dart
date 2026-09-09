import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_log_panel.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_row.dart';

const _exercise = PlanExercise(
  planExerciseId: 601,
  exerciseId: 101,
  name: 'Goblet squat',
  muscleGroup: 'quadriceps',
  orderNo: 1,
  targetSets: 3,
  targetReps: '8-12',
);

ActiveSession _session({List<LoggedSet> sets = const []}) => ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      sets: sets,
    );

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  // How many sets are done is not repeated here: the ticks down the table say
  // it, and the jump sheet carries it per exercise. The card header is the
  // name and the prescription, as the mockup draws it.
  testWidgets('names the exercise and its prescription', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
      ]),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Target 3 × 8-12'), findsOneWidget);
  });

  // The unit only ever existed as the weight field's hint, which disappears
  // the moment a value is typed -- so a logged set showed a bare number with
  // nothing on screen saying what it measured. The header is what keeps the
  // columns named whatever the fields contain.
  testWidgets('the set table labels its columns', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    final header = find.byKey(const Key('logpanel.columns'));
    expect(find.descendant(of: header, matching: find.text('SET')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('KG')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('REPS')), findsOneWidget);
  });

  testWidgets('the column header switches the unit', (tester) async {
    WeightUnit? chosen;
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      unit: WeightUnit.kg,
      onUnitChanged: (unit) => chosen = unit,
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    await tester.tap(find.byKey(const Key('unit.lb')));
    expect(chosen, WeightUnit.lb);
  });

  // One pound is 0.45359237 kg exactly, so 22.5 kg is 49.6039... lb, 25 kg is
  // 55.1155... lb and the 2.5 kg gain between them is 5.5115... lb. Derived by
  // hand: an expectation run through the same conversion the widget uses
  // would pass whatever factor that was.
  testWidgets('in pounds, every weight on the panel reads in pounds',
      (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 25, reps: 8),
      ]),
      last: const LastPerformance(
        exerciseId: 101, weightKg: 22.5, reps: 10, sessionDate: '2026-09-05',
      ),
      unit: WeightUnit.lb,
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.text('Target 3 × 8-12 · last 49.6 lb'), findsOneWidget);
    expect(
      find.text('+5.5 lb vs last session — nice progressive overload.'),
      findsOneWidget,
    );
    // The stored set, and the next row prefilled from last week.
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).controller!.text,
      '55.1',
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.2.weight'))).controller!.text,
      '49.6',
    );
  });

  // The storage contract: whatever unit is on screen, the server is handed
  // kilograms. A conversion missing here silently records a 100 lb lift as
  // 100 kg and corrupts every figure downstream of it.
  testWidgets('a weight typed in pounds is reported in kilograms',
      (tester) async {
    double? sentKg;
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      unit: WeightUnit.lb,
      onCompleteSet: (_, weightKg, _) async => sentKg = weightKg,
      onUndoSet: (_) async {},
    )));

    await tester.enterText(find.byKey(const Key('set.1.weight')), '100');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(sentKg, closeTo(45.359237, 1e-9));
  });

  // Flipping the unit must carry the number across, not leave it sitting
  // there meaning something else. Someone who has typed 100 kg and then
  // realises the app is in the wrong unit would otherwise log 100 lb.
  testWidgets('switching the unit converts a half-typed weight in place',
      (tester) async {
    var unit = WeightUnit.kg;
    await tester.pumpWidget(MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: ExerciseLogPanel(
              exercise: _exercise,
              session: _session(),
              unit: unit,
              onUnitChanged: (chosen) => setState(() => unit = chosen),
              onCompleteSet: (_, _, _) async {},
              onUndoSet: (_) async {},
            ),
          ),
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('set.1.weight')), '100');
    await tester.tap(find.byKey(const Key('unit.lb')));
    await tester.pumpAndSettle();

    // 100 kg is 220.462... lb.
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).controller!.text,
      '220.5',
    );
  });

  // The mockup highlights the set you are about to do, not the ones already
  // finished. Without it every empty row looks the same and nothing on screen
  // says which one is next.
  testWidgets('the next unlogged set is the highlighted one', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
      ]),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    // Three target sets: the first is done, so the second is next.
    expect(
      tester.widgetList<SetRow>(find.byType(SetRow)).map((row) => row.active),
      [false, true, false],
    );
  });

  testWidgets('a finished exercise highlights nothing', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
        LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
        LoggedSet(exerciseId: 101, setNumber: 3, weightKg: 20, reps: 10),
      ]),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(
      tester.widgetList<SetRow>(find.byType(SetRow)).map((row) => row.active),
      [false, false, false],
    );
  });

  testWidgets('shows one row per target set', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.byKey(const Key('set.1.weight')), findsOneWidget);
    expect(find.byKey(const Key('set.3.reps')), findsOneWidget);
    expect(find.byKey(const Key('set.4.weight')), findsNothing);
  });

  testWidgets('the weight field is prefilled from the last session', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      last: const LastPerformance(
        exerciseId: 101, weightKg: 22.5, reps: 10, sessionDate: '2026-09-05',
      ),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.text('Target 3 × 8-12 · last 22.5 kg'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('set.1.weight')));
    expect(field.controller!.text, '22.5');
  });

  testWidgets('a first session prefills nothing and says nothing', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.textContaining('Last '), findsNothing);
    final field = tester.widget<TextField>(find.byKey(const Key('set.1.weight')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('ticking a set reports the typed weight and reps', (tester) async {
    int? gotSet;
    double? gotWeight;
    int? gotReps;

    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      onCompleteSet: (setNumber, weightKg, reps) async {
        gotSet = setNumber;
        gotWeight = weightKg;
        gotReps = reps;
      },
      onUndoSet: (_) async {},
    )));

    await tester.enterText(find.byKey(const Key('set.1.weight')), '25');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(gotSet, 1);
    expect(gotWeight, 25.0);
    expect(gotReps, 8);
  });

  testWidgets('an empty weight is sent as null, not zero', (tester) async {
    double? gotWeight = 99;
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      onCompleteSet: (_, weightKg, _) async => gotWeight = weightKg,
      onUndoSet: (_) async {},
    )));

    await tester.enterText(find.byKey(const Key('set.1.reps')), '15');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    // A bodyweight set has no load. Zero would claim they lifted nothing,
    // which is a different statement from "there was nothing to lift".
    expect(gotWeight, isNull);
  });

  testWidgets('a failed write leaves the row unticked and shows a retry', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      onCompleteSet: (_, _, _) async => throw Exception('offline'),
      onUndoSet: (_) async {},
    )));

    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('beating the last session shows the overload nudge', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 25, reps: 8),
      ]),
      last: const LastPerformance(
        exerciseId: 101, weightKg: 22.5, reps: 10, sessionDate: '2026-09-05',
      ),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(
      find.text('+2.5 kg vs last session — nice progressive overload.'),
      findsOneWidget,
    );
  });

  testWidgets('matching or missing the last weight shows no nudge', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 22.5, reps: 8),
      ]),
      last: const LastPerformance(
        exerciseId: 101, weightKg: 22.5, reps: 10, sessionDate: '2026-09-05',
      ),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    // Equalling last week is not progressive overload, and saying it is would
    // make the nudge meaningless.
    expect(find.textContaining('vs last session'), findsNothing);
  });

  testWidgets('a first session never nudges', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 40, reps: 8),
      ]),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.textContaining('vs last session'), findsNothing);
  });

  testWidgets('a stored set renders ticked and read-only', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 22.5, reps: 10),
      ]),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    final field = tester.widget<TextField>(find.byKey(const Key('set.1.weight')));
    expect(field.controller!.text, '22.5');
    expect(field.enabled, isFalse);
  });

  testWidgets('tapping a ticked set un-ticks it', (tester) async {
    int? undone;
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 22.5, reps: 10),
      ]),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (setNumber) async => undone = setNumber,
    )));

    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(undone, 1);
  });

  // --- Additions beyond the brief's list ---

  testWidgets(
      'the row disables the weight, reps and tick controls while the write '
      'is in flight, then ticks once it resolves', (tester) async {
    final completer = Completer<void>();
    ActiveSession session = _session();

    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => _host(ExerciseLogPanel(
        exercise: _exercise,
        session: session,
        onCompleteSet: (setNumber, weightKg, reps) async {
          await completer.future;
          setState(() {
            session = session.withSet(LoggedSet(
              exerciseId: _exercise.exerciseId,
              setNumber: setNumber,
              weightKg: weightKg,
              reps: reps,
            ));
          });
        },
        onUndoSet: (_) async {},
      )),
    ));

    await tester.enterText(find.byKey(const Key('set.1.weight')), '25');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pump();

    // Still in flight: nothing on this row can be touched.
    expect(tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).enabled, isFalse);
    expect(tester.widget<TextField>(find.byKey(const Key('set.1.reps'))).enabled, isFalse);
    expect(tester.widget<InkWell>(find.byKey(const Key('set.1.tick'))).onTap, isNull);

    completer.complete();
    await tester.pumpAndSettle();

    // Resolved: the write-through guarantee held, so now it ticks.
    // The mockup's mark: a bare accent check, not a filled circle.
    expect(find.byIcon(Icons.check), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('set.1.weight')));
    expect(field.enabled, isFalse);
    expect(field.controller!.text, '25');
  });

  testWidgets('un-ticking a set does not leave the old value sitting in the field',
      (tester) async {
    ActiveSession session = _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 22.5, reps: 10),
    ]);

    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => _host(ExerciseLogPanel(
        exercise: _exercise,
        session: session,
        onCompleteSet: (_, _, _) async {},
        onUndoSet: (setNumber) async {
          setState(() {
            session = session.withoutSet(_exercise.exerciseId, setNumber);
          });
        },
      )),
    ));

    // Sanity: starts ticked, showing the stored value.
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).controller!.text,
      '22.5',
    );

    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    // The row must rebuild its controller on un-tick, not keep showing the
    // set that was just undone as though it were still typed in.
    final field = tester.widget<TextField>(find.byKey(const Key('set.1.weight')));
    expect(field.controller!.text, isEmpty);
    expect(field.enabled, isTrue);
  });
}
