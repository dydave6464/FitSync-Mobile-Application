import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_log_panel.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';
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

/// A fresh store per test, torn down with the test.
SetDrafts _drafts(WidgetTester tester) {
  final drafts = SetDrafts();
  addTearDown(drafts.dispose);
  return drafts;
}

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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
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

  // The kg-on-write contract this used to verify (parseWeight('100', lb) ==
  // 45.359237) is unchanged and covered on its own in units_test.dart. What
  // this test can still say at the panel level is that the tick no longer
  // performs that conversion-and-report cycle itself -- that call moved off
  // SetRow entirely and does not land again until the footer button reads
  // the same field (logger_action.dart, a later task). A typed value the tap
  // does not consume is the visible sign that nothing fired.
  testWidgets('a weight typed in pounds is left untouched by an unlogged tap',
      (tester) async {
    double? sentKg;
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      unit: WeightUnit.lb,
      drafts: _drafts(tester),
      onCompleteSet: (_, weightKg, _) async => sentKg = weightKg,
      onUndoSet: (_) async {},
    )));

    await tester.enterText(find.byKey(const Key('set.1.weight')), '100');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(sentKg, isNull);
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).controller!.text,
      '100',
    );
  });

  // Flipping the unit must carry the number across, not leave it sitting
  // there meaning something else. Someone who has typed 100 kg and then
  // realises the app is in the wrong unit would otherwise log 100 lb.
  testWidgets('switching the unit converts a half-typed weight in place',
      (tester) async {
    var unit = WeightUnit.kg;
    final drafts = _drafts(tester);
    await tester.pumpWidget(MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: ExerciseLogPanel(
              exercise: _exercise,
              session: _session(),
              unit: unit,
              // The panel itself has no unit-conversion side effect any
              // more -- that moved to SetDrafts.convert(), called by
              // whoever owns the toggle. session_logger_screen.dart's
              // _setUnit does this in the real app; mirrored here since
              // this test drives the panel directly.
              onUnitChanged: (chosen) => setState(() {
                drafts.convert(unit, chosen);
                unit = chosen;
              }),
              drafts: drafts,
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.text('Target 3 × 8-12 · last 22.5 kg'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('set.1.weight')));
    expect(field.controller!.text, '22.5');
  });

  testWidgets('the reps field is prefilled from the last session', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      last: const LastPerformance(
        exerciseId: 101, weightKg: 22.5, reps: 10, sessionDate: '2026-09-05',
      ),
      drafts: _drafts(tester),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    final field = tester.widget<TextField>(find.byKey(const Key('set.1.reps')));
    expect(field.controller!.text, '10');
  });

  // The regression that made repeating a workout feel like typing it from
  // scratch. /sessions/last-performance is a fetch, so the first frame of the
  // logger always renders with `last` still null -- and the row is keyed on the
  // stored set's presence, not on the prefill, so its State survives the
  // rebuild that brings the values in. Reading them in initState alone means
  // the header says "last 22.5 kg" over two empty fields, forever.
  testWidgets('a prefill arriving after the first frame still reaches the fields',
      (tester) async {
    final drafts = _drafts(tester);
    Widget panel(LastPerformance? last) => _host(ExerciseLogPanel(
          exercise: _exercise,
          session: _session(),
          last: last,
          drafts: drafts,
          onCompleteSet: (_, _, _) async {},
          onUndoSet: (_) async {},
        ));

    await tester.pumpWidget(panel(null));
    await tester.pumpWidget(panel(const LastPerformance(
      exerciseId: 101, weightKg: 22.5, reps: 10, sessionDate: '2026-09-05',
    )));

    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).controller!.text,
      '22.5',
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.reps'))).controller!.text,
      '10',
    );
  });

  // A late prefill fills a field, it does not correct one. Someone who opened
  // the logger and started typing before the fetch landed must not have their
  // first set rewritten under them.
  testWidgets('a late prefill leaves a value already typed alone', (tester) async {
    final drafts = _drafts(tester);
    Widget panel(LastPerformance? last) => _host(ExerciseLogPanel(
          exercise: _exercise,
          session: _session(),
          last: last,
          drafts: drafts,
          onCompleteSet: (_, _, _) async {},
          onUndoSet: (_) async {},
        ));

    await tester.pumpWidget(panel(null));
    await tester.enterText(find.byKey(const Key('set.1.weight')), '30');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '6');

    await tester.pumpWidget(panel(const LastPerformance(
      exerciseId: 101, weightKg: 22.5, reps: 10, sessionDate: '2026-09-05',
    )));

    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).controller!.text,
      '30',
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.reps'))).controller!.text,
      '6',
    );
  });

  testWidgets('a first session prefills nothing and says nothing', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      drafts: _drafts(tester),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (_) async {},
    )));

    expect(find.textContaining('Last '), findsNothing);
    final field = tester.widget<TextField>(find.byKey(const Key('set.1.weight')));
    expect(field.controller!.text, isEmpty);
  });

  // The tick used to be what logged a set; it moved off SetRow entirely in
  // this task (a footer button reads the same drafted fields instead, in a
  // later task). What is left to verify at this layer is that an unlogged
  // row's mark genuinely does nothing -- no report, no consumed text.
  testWidgets('an unlogged row does not report anything on tap', (tester) async {
    int? gotSet;
    double? gotWeight;
    int? gotReps;

    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      drafts: _drafts(tester),
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

    expect(gotSet, isNull);
    expect(gotWeight, isNull);
    expect(gotReps, isNull);
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).controller!.text,
      '25',
    );
  });

  // parseWeight('', ...) returning null -- so an empty field is never sent
  // as a zero -- is covered directly in units_test.dart. Here, the same as
  // above: a tap on an unlogged row must not consume or report the field.
  testWidgets('an unlogged row leaves an empty weight field alone on tap',
      (tester) async {
    double? gotWeight = 99;
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      drafts: _drafts(tester),
      onCompleteSet: (_, weightKg, _) async => gotWeight = weightKg,
      onUndoSet: (_) async {},
    )));

    await tester.enterText(find.byKey(const Key('set.1.reps')), '15');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(gotWeight, 99);
    expect(
      tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).controller!.text,
      isEmpty,
    );
  });

  // The inline Retry this used to show moved with the write itself -- there
  // is no failure state left on SetRow to render it from. A tap that reaches
  // nothing must leave no trace of one either.
  testWidgets('an unlogged row shows no retry affordance after a tap', (tester) async {
    await tester.pumpWidget(_host(ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      drafts: _drafts(tester),
      onCompleteSet: (_, _, _) async => throw Exception('offline'),
      onUndoSet: (_) async {},
    )));

    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing);
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
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
      drafts: _drafts(tester),
      onCompleteSet: (_, _, _) async {},
      onUndoSet: (setNumber) async => undone = setNumber,
    )));

    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(undone, 1);
  });

  // --- Additions beyond the brief's list ---

  // SetRow no longer owns a busy flag of its own -- the write itself now
  // happens at the footer button (logger_action.dart, coming in a later
  // task), which is what the in-flight *behaviour* is re-tested against.
  // What stays this row's job is rendering whatever busy state it is handed.
  testWidgets(
      'the row disables the weight and reps controls while the write is in flight',
      (tester) async {
    await tester.pumpWidget(_host(SetRow(
      setNumber: 1,
      logged: null,
      drafts: _drafts(tester),
      busy: true,
    )));

    expect(tester.widget<TextField>(find.byKey(const Key('set.1.weight'))).enabled, isFalse);
    expect(tester.widget<TextField>(find.byKey(const Key('set.1.reps'))).enabled, isFalse);
  });

  testWidgets('un-ticking a set does not leave the old value sitting in the field',
      (tester) async {
    ActiveSession session = _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 22.5, reps: 10),
    ]);
    final drafts = _drafts(tester);

    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => _host(ExerciseLogPanel(
        exercise: _exercise,
        session: session,
        drafts: drafts,
        onCompleteSet: (_, _, _) async {},
        onUndoSet: (setNumber) async {
          setState(() {
            session = session.withoutSet(_exercise.exerciseId, setNumber);
            // Releasing the draft on undo is the caller's job now that the
            // panel no longer owns the fields -- session_logger_screen.dart
            // does the same once it reaches this call (a later task).
            // Without it, seed() has nothing to fill an empty field with,
            // since it never overwrites one that already holds text.
            drafts.release(setNumber);
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
