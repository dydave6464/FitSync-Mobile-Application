import 'dart:async';

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
  testWidgets('shows the prescription and how many sets are done', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
      ]),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('3 × 8-12'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
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
    expect(find.descendant(of: header, matching: find.text('Set')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('kg')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('reps')), findsOneWidget);
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

    expect(find.text('Last 22.5 kg × 10'), findsOneWidget);
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

    expect(find.text('+2.5 kg vs last session'), findsOneWidget);
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
    expect(tester.widget<IconButton>(find.byKey(const Key('set.1.tick'))).onPressed, isNull);

    completer.complete();
    await tester.pumpAndSettle();

    // Resolved: the write-through guarantee held, so now it ticks.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
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
