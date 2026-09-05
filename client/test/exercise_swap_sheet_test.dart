import 'dart:async';

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

const _plan = WorkoutPlan(
  planId: 1, name: 'P', splitStyle: 'full_body', daysPerWeek: 3,
  sessionLengthMin: 45, weekNo: 1, exercises: [],
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
          {String? q, bool bodyweightOnly = false}) async =>
      const [];

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async =>
      throw const ApiException(
          'EXERCISE_NOT_ALLOWED', 'That exercise is not available for this plan.');
}

/// A [PlanRepository] whose swap always succeeds immediately.
class _SucceedingRepo implements PlanRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan?> activePlan() async => _plan;

  @override
  Future<List<ExerciseAlternative>> alternatives(int planExerciseId,
          {String? q, bool bodyweightOnly = false}) async =>
      const [_alt];

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async => _plan;
}

/// A [PlanRepository] whose swap does not resolve until [completer] does —
/// lets a test dismiss the sheet while the request is still in flight.
class _SlowRepo implements PlanRepository {
  _SlowRepo(this.completer);

  final Completer<WorkoutPlan> completer;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan?> activePlan() async => _plan;

  @override
  Future<List<ExerciseAlternative>> alternatives(int planExerciseId,
          {String? q, bool bodyweightOnly = false}) async =>
      const [_alt];

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) => completer.future;
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

  testWidgets('offers a bodyweight-only filter', (tester) async {
    await _pump(tester, const [_alt]);

    expect(find.text('Bodyweight only'), findsOneWidget);
  });

  testWidgets('tapping the filter re-queries with it set', (tester) async {
    final asked = <bool>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        alternativesProvider.overrideWith((ref, key) async {
          asked.add(key.bodyweightOnly);
          return const [_alt];
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ExerciseSwapSheet(planExerciseId: 77, exerciseName: 'Cable Fly'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bodyweight only'));
    await tester.pumpAndSettle();

    expect(asked, [false, true],
        reason: 'the filter has to reach the server, not filter the fetched page');
  });

  testWidgets(
      'the empty state names bodyweight-only as the cause when that filter emptied the list',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        alternativesProvider.overrideWith(
            (ref, key) async => key.bodyweightOnly ? const [] : const [_alt]),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ExerciseSwapSheet(planExerciseId: 77, exerciseName: 'Lateral Raise'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('swap.bodyweightOnly')));
    await tester.pumpAndSettle();

    // Reachable in production per spec §7: delts has no body-weight strength
    // rows at all, so a user with a full gym who ticks this chip for a
    // shoulder exercise gets zero alternatives. The filter they just set
    // emptied the list, not their equipment, so the equipment-cause message
    // must not appear here.
    expect(find.textContaining('Nothing you can do with your equipment'), findsNothing,
        reason: 'the filter, not the equipment, is why the list is empty');
    expect(find.textContaining('Bodyweight only'), findsWidgets,
        reason: 'the empty state must name the filter as the cause');
  });

  testWidgets(
      'a successful swap invalidates every cached alternatives list, not just this row',
      (tester) async {
    var fetches = 0;
    final container = ProviderContainer(overrides: [
      alternativesProvider.overrideWith((ref, key) async {
        fetches++;
        return const [_alt];
      }),
      planRepositoryProvider.overrideWithValue(_SucceedingRepo()),
    ]);
    addTearDown(container.dispose);

    // Held outside the sheet's widget tree, on the very key the sheet
    // itself watches, so it is not torn down when the sheet closes below —
    // isolating the family-wide invalidate in `_choose` from auto-dispose,
    // which would also eventually reclaim a genuinely-unwatched entry on
    // its own and could make this pass for the wrong reason.
    const key = (planExerciseId: 77, query: '', bodyweightOnly: false);
    container.listen(alternativesProvider(key), (_, _) {});

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: ExerciseSwapSheet(planExerciseId: 77, exerciseName: 'Cable Fly'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(fetches, 1, reason: 'one fetch renders the initial list');

    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pumpAndSettle();

    expect(fetches, 2,
        reason: 'a swap changes inPlanIds for every row in the plan, so every '
            'cached alternatives list — including this exact key — must be '
            'refetched, not just the row that changed');
  });

  testWidgets('a swap in flight when the sheet is dismissed still refreshes the plan',
      (tester) async {
    final completer = Completer<WorkoutPlan>();
    var activePlanFetches = 0;
    final container = ProviderContainer(overrides: [
      planRepositoryProvider.overrideWithValue(_SlowRepo(completer)),
      alternativesProvider.overrideWith((ref, key) async => const [_alt]),
      activePlanProvider.overrideWith((ref) {
        activePlanFetches++;
        return Future.value(_plan);
      }),
    ]);
    addTearDown(container.dispose);

    // Held outside the sheet's widget tree so it survives the sheet's
    // disposal below — asserting on the (by then disposed) sheet's own
    // state would prove nothing about whether the refresh actually reached
    // the provider.
    container.listen(activePlanProvider, (_, _) {});
    await container.read(activePlanProvider.future);
    expect(activePlanFetches, 1);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: ExerciseSwapSheet(planExerciseId: 77, exerciseName: 'Cable Fly'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pump(); // starts the swap; it awaits the completer, so it does not resolve yet

    // Dismiss the sheet by replacing the whole widget tree under it — the
    // sheet's State is disposed while its swap() call is still in flight,
    // exactly as it would be if the user swiped the sheet away mid-request.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));
    await tester.pump();

    completer.complete(_plan);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'completing the swap after disposal must not throw');
    expect(activePlanFetches, 2,
        reason: 'the refresh must survive the sheet being disposed mid-request');
  });
}
