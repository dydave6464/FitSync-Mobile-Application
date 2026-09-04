import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/exercise_alternative.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/exercise_swap_sheet.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';

const _alt = ExerciseAlternative(
  exerciseId: 12, name: 'Push-up', muscleGroup: 'pectorals', equipment: 'Bodyweight',
);

/// A minimal [PlanRepository] whose swap always fails, so the sheet's error
/// path can be exercised without a mock framework — the interface is small
/// enough to implement directly.
class _FailingRepo implements PlanRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan?> activePlan() async => null;

  @override
  Future<List<ExerciseAlternative>> alternatives(int planExerciseId,
          {String? q}) async =>
      const [];

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async =>
      throw const ApiException(
          'EXERCISE_NOT_ALLOWED', 'That exercise is not available for this plan.');
}

Future<void> _pump(WidgetTester tester, List<ExerciseAlternative> rows) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      alternativesProvider.overrideWith((ref, key) async => rows),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: ExerciseSwapSheet(planExerciseId: 77, exerciseName: 'Cable Fly'),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('names the exercise being replaced', (tester) async {
    await _pump(tester, const [_alt]);

    expect(find.text('Replace Cable Fly'), findsOneWidget);
  });

  testWidgets('lists the alternatives', (tester) async {
    await _pump(tester, const [_alt]);

    expect(find.text('Push-up'), findsOneWidget);
    expect(find.text('Bodyweight'), findsOneWidget);
  });

  testWidgets('explains an empty pool rather than showing a blank list',
      (tester) async {
    await _pump(tester, const []);

    // Reachable in production: delts has no body-weight strength exercises at
    // all, so a user who owns nothing gets zero alternatives for a shoulder.
    expect(find.textContaining('Nothing you can do'), findsOneWidget);
  });

  testWidgets('a failed swap keeps the sheet open with the message',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        alternativesProvider.overrideWith((ref, key) async => const [_alt]),
        planRepositoryProvider.overrideWithValue(_FailingRepo()),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ExerciseSwapSheet(planExerciseId: 77, exerciseName: 'Cable Fly'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseSwapSheet), findsOneWidget,
        reason: 'closing would discard the choice the user just made');
    expect(find.textContaining('not available'), findsOneWidget);
  });
}
