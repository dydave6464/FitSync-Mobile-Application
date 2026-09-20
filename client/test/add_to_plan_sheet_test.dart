import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/add_to_plan_sheet.dart';

const _plan = WorkoutPlan(
  planId: 9,
  name: 'My Push / Pull / Legs',
  splitStyle: 'push_pull_legs',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  source: 'custom',
  exercises: [
    PlanExercise(
      planExerciseId: 1,
      exerciseId: 101,
      name: 'Bench press',
      muscleGroup: 'chest',
      orderNo: 1,
      targetSets: 3,
      targetReps: '8-12',
      dayNo: 1,
    ),
    PlanExercise(
      planExerciseId: 2,
      exerciseId: 202,
      name: 'Barbell row',
      muscleGroup: 'back',
      orderNo: 1,
      targetSets: 3,
      targetReps: '8-12',
      dayNo: 2,
    ),
  ],
);

/// [chosen] reads whatever the sheet has resolved to *at the moment it is
/// called* -- useful only after a caller has driven the sheet to a result,
/// since right after [_open] returns the sheet is still open and nothing has
/// resolved yet.
typedef _Opened = ({AddToPlanChoice? Function() chosen});

Future<_Opened> _open(WidgetTester tester) async {
  AddToPlanChoice? chosen;
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              chosen = await showAddToPlanSheet(context, _plan);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (chosen: () => chosen);
}

void main() {
  testWidgets('lists the days already in the plan', (tester) async {
    await _open(tester);

    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 2'), findsOneWidget);
    expect(find.byKey(const Key('addToPlan.newDay')), findsOneWidget);
  });

  testWidgets('says how much is in each day', (tester) async {
    // "Replace day 2" is not a decision anyone can make without knowing what
    // day 2 currently holds.
    await _open(tester);

    expect(find.textContaining('1 exercise'), findsWidgets);
  });

  testWidgets('a new day is a choice with no day to replace', (tester) async {
    final opened = await _open(tester);

    await tester.tap(find.byKey(const Key('addToPlan.newDay')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(opened.chosen(), (cancelled: false, dayNo: null));
  });

  testWidgets('choosing a day resolves to that day', (tester) async {
    final opened = await _open(tester);

    await tester.tap(find.byKey(const Key('addToPlan.day.2')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(opened.chosen(), (cancelled: false, dayNo: 2));
  });

  testWidgets('dismissing the sheet is none of these, not a new day', (
    tester,
  ) async {
    // "As a new day" is a row the user can tap. Swiping the sheet away or
    // tapping outside it conventionally means "none of these" -- and a day
    // added by accident cannot be removed again: pruning a custom plan is
    // explicitly out of scope, so the extra day is permanent.
    final opened = await _open(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(opened.chosen(), (cancelled: true, dayNo: null));
  });
}
