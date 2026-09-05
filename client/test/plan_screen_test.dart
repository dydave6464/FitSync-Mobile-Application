import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/presentation/exercise_detail_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/exercise_alternative.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/exercise_swap_sheet.dart';
import 'package:fitsync/features/plans/presentation/plan_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';

const _plan = WorkoutPlan(
  planId: 42,
  name: 'Week 1 — Full body',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [
    PlanExercise(
      planExerciseId: 601,
      exerciseId: 101,
      name: 'Goblet squat',
      muscleGroup: 'quadriceps',
      orderNo: 1,
      targetSets: 3,
      targetReps: '8-12',
    ),
    PlanExercise(
      planExerciseId: 602,
      exerciseId: 102,
      name: 'Push-up',
      muscleGroup: 'chest',
      orderNo: 2,
      targetSets: 3,
      targetReps: '10-15',
    ),
  ],
);

/// Keeps anything downstream of the API client off the platform channel.
ApiClient _hermeticClient() => ApiClient(
      baseUrl: 'http://test.local',
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient((_) async => http.Response('{"data":{}}', 200)),
    );

Future<void> _pump(
  WidgetTester tester,
  WorkoutPlan? plan, {
  List<ExerciseAlternative>? alternatives,
  VoidCallback? onGoToProfile,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(_hermeticClient()),
      activePlanProvider.overrideWith((ref) async => plan),
      // Only stubbed for the tests that open the sheet; the others never
      // reach it, and an unconditional override would hide a regression
      // where the sheet fetches when it should not.
      if (alternatives != null)
        alternativesProvider.overrideWith((ref, key) async => alternatives),
    ],
    child: MaterialApp(home: PlanScreen(onGoToProfile: onGoToProfile)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the plan summary', (tester) async {
    await _pump(tester, _plan);

    expect(find.text('Week 1 — Full body'), findsOneWidget);
    expect(find.textContaining('3 days a week'), findsOneWidget);
    expect(find.textContaining('Full body'), findsWidgets);
  });

  testWidgets('renders every exercise with its sets and reps', (tester) async {
    await _pump(tester, _plan);

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Push-up'), findsOneWidget);
    expect(find.textContaining('3 × 8-12'), findsOneWidget);
    expect(find.textContaining('3 × 10-15'), findsOneWidget);
  });

  testWidgets('tapping an exercise opens its detail screen', (tester) async {
    await _pump(tester, _plan);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
  });

  testWidgets('no plan yet renders an empty state, not a crash',
      (tester) async {
    await _pump(tester, null);

    expect(find.byKey(const Key('noPlan')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every plan exercise offers a way to change it', (tester) async {
    await _pump(tester, _plan);

    expect(find.text('Change'), findsNWidgets(_plan.exercises.length));
  });

  testWidgets('Change opens the swap sheet for that exercise', (tester) async {
    await _pump(tester, _plan, alternatives: const []);

    // Keyed by plan row, not by index: tapping the second card must open the
    // sheet for the second exercise, which a `find.text('Change').first` tap
    // could never catch.
    await tester.tap(find.byKey(const Key('swap.open.602')));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseSwapSheet), findsOneWidget);
    expect(find.text('Replace Push-up'), findsOneWidget);
  });

  testWidgets('a row with no artwork falls back to its equipment, not a dumbbell',
      (tester) async {
    // Network images never load in a widget test, so what renders here is the
    // same fallback a missing file produces in the app. A body-weight exercise
    // showing a dumbbell was the complaint; it now shows a body.
    await _pump(
      tester,
      const WorkoutPlan(
        planId: 42, name: 'W', splitStyle: 'full_body', daysPerWeek: 3,
        sessionLengthMin: 45, weekNo: 1,
        exercises: [
          PlanExercise(
            planExerciseId: 601, exerciseId: 101, name: 'Push-up',
            muscleGroup: 'pectorals', orderNo: 1, targetSets: 3,
            targetReps: '8-12', equipment: 'Bodyweight',
          ),
        ],
      ),
    );

    expect(find.byIcon(Icons.accessibility_new), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center), findsNothing);
  });

  testWidgets('the sheet opens just below the Exercises heading', (tester) async {
    // Pins the sheet's height fraction to the thing it was chosen for. The
    // constant lives in exercise_swap_sheet.dart, but what makes 0.66 right
    // is this screen: the heading stays visible and the plan behind it is
    // still recognisable. Anyone retuning the constant sees this fail rather
    // than discovering on a device that the sheet swallowed the page.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await _pump(tester, _plan, alternatives: const []);
    await tester.tap(find.byKey(const Key('swap.open.601')));
    await tester.pumpAndSettle();

    final heading = tester.getBottomLeft(find.text('EXERCISES')).dy;
    final sheetTop = tester.getTopLeft(find.byType(ExerciseSwapSheet)).dy;

    // Only the "stays visible" half is asserted: the exact gap moves with the
    // plan card above it, which grows a line whenever a plan name wraps, so
    // pinning the distance would fail on a long plan name and prove nothing.
    expect(sheetTop, greaterThanOrEqualTo(heading),
        reason: 'the sheet must not swallow the heading it opens under');
  });

  testWidgets("the sheet's equipment note closes it and heads for Profile",
      (tester) async {
    var asked = 0;
    await _pump(tester, _plan, alternatives: const [], onGoToProfile: () => asked++);

    await tester.tap(find.byKey(const Key('swap.open.602')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('swap.equipmentHint')));
    await tester.pumpAndSettle();

    expect(asked, 1, reason: 'the note has to reach the screen that owns the tabs');
    expect(find.byType(ExerciseSwapSheet), findsNothing,
        reason: 'a sheet left open would cover the tab it just switched to');
  });
}
