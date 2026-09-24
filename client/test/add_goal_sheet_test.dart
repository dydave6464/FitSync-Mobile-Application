import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show weightUnitProvider;
import 'package:fitsync/features/streaks/data/streaks_repository.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/add_goal_sheet.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart';

const _bench = GoalOption(
  exerciseId: 3,
  name: 'Bench Press',
  bestKg: 52.5,
  sets: 6,
);

ExerciseSummary _summary(int id, String name) => ExerciseSummary(
  exerciseId: id,
  name: name,
  muscleGroup: 'chest',
  equipment: null,
  thumbnailUrl: null,
);

/// Records adds; `failAdd` makes the next add throw it.
class _FakeGoalsRepo implements GoalsRepository {
  _FakeGoalsRepo(this._options);

  final List<GoalOption> _options;
  final added = <(int, double)>[];
  Object? failAdd;
  Completer<void>? blockAdd;

  @override
  Future<List<GoalOption>> options() async => _options;

  @override
  Future<List<LiftGoal>> list() async {
    // Return the goals that were added.
    return added
        .map(
          (e) => LiftGoal(
            goalId: 1,
            exerciseId: e.$1,
            exerciseName: 'x',
            targetKg: e.$2,
            bestKg: null,
            reachedOn: null,
          ),
        )
        .toList();
  }

  @override
  Future<LiftGoal> add({
    required int exerciseId,
    required double targetKg,
  }) async {
    if (blockAdd != null) await blockAdd!.future;
    if (failAdd != null) throw failAdd!;
    added.add((exerciseId, targetKg));
    return LiftGoal(
      goalId: 1,
      exerciseId: exerciseId,
      exerciseName: 'x',
      targetKg: targetKg,
      bestKg: null,
      reachedOn: null,
    );
  }

  @override
  Future<void> remove(int goalId) async {}
}

Future<_FakeGoalsRepo> _open(
  WidgetTester tester, {
  List<GoalOption> options = const [_bench],
  WeightUnit unit = WeightUnit.kg,
  List<ExerciseSummary> results = const [],
}) async {
  final repo = _FakeGoalsRepo(options);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        goalsRepositoryProvider.overrideWithValue(repo),
        weightUnitProvider.overrideWithValue(unit),
        goalSearchProvider.overrideWith((ref, query) async => results),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAddGoalSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

/// The search field waits 300 ms before searching; pumpAndSettle alone does
/// not wait on a Timer.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('goal.search')), text);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _setTarget(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('goal.target')), text);
  await tester.tap(find.byKey(const Key('goal.save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists what you have lifted, each with its best', (tester) async {
    await _open(tester);

    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('LIFTED BEFORE'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Best 52.5 kg'), findsOneWidget);
  });

  testWidgets('with nothing lifted it points to search', (tester) async {
    await _open(tester, options: const []);

    expect(find.text('Search for an exercise to set a goal.'), findsOneWidget);
  });

  testWidgets('typing searches the whole catalogue', (tester) async {
    await _open(tester, results: [_summary(8, 'Deadlift')]);

    await _search(tester, 'dead');

    expect(find.text('Deadlift'), findsOneWidget);
    expect(find.text('LIFTED BEFORE'), findsNothing);
  });

  testWidgets('picking and saving sends the target in kilograms', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    expect(find.text('Your best: 52.5 kg'), findsOneWidget);
    await _setTarget(tester, '60');

    expect(repo.added, [(3, 60.0)]);
    expect(find.byKey(const Key('goal.save')), findsNothing, reason: 'closed');
  });

  testWidgets('a pound target is shown and sent correctly', (tester) async {
    final repo = await _open(tester, unit: WeightUnit.lb);

    expect(find.text('Best 115.7 lb'), findsOneWidget);
    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await _setTarget(tester, '135');

    // 135 lb = 61.234... kg, sent to two decimals.
    expect(repo.added.single.$1, 3);
    expect(repo.added.single.$2, closeTo(61.23, 0.0001));
  });

  testWidgets('a target at or below your best is refused in the sheet', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await _setTarget(tester, '50');

    expect(find.text('Your best is already 52.5 kg.'), findsOneWidget);
    expect(repo.added, isEmpty);
    expect(find.byKey(const Key('goal.save')), findsOneWidget);
  });

  testWidgets(
    'a pound target that only beats the best before rounding is refused',
    (tester) async {
      const bench = GoalOption(
        exerciseId: 3,
        name: 'Bench Press',
        bestKg: 61.23,
        sets: 6,
      );
      final repo = await _open(tester, options: [bench], unit: WeightUnit.lb);

      await tester.tap(find.byKey(const Key('goal.option.3')));
      await tester.pumpAndSettle();
      await _setTarget(tester, '135');

      // 135 lb is 61.23497 kg unrounded -- just above the 61.23 kg best -- but
      // rounds to the same 61.23 kg that is actually sent, so it must be
      // refused in the user's own unit, not the server's kilogram message.
      expect(
        find.text(
          'Your best is already ${formatWeightWithUnit(61.23, WeightUnit.lb)}.',
        ),
        findsOneWidget,
      );
      expect(repo.added, isEmpty);
    },
  );

  testWidgets('an empty target asks for one', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await _setTarget(tester, '');

    expect(find.text('Enter a target weight.'), findsOneWidget);
  });

  testWidgets('a target above the server range is refused in the sheet', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await _setTarget(tester, '1000');

    expect(
      find.text(
        'Enter a target between ${formatWeightWithUnit(0.5, WeightUnit.kg)} '
        'and ${formatWeightWithUnit(999.99, WeightUnit.kg)}.',
      ),
      findsOneWidget,
    );
    expect(repo.added, isEmpty);
  });

  testWidgets('a server refusal stays in the sheet', (tester) async {
    final repo = await _open(tester);
    repo.failAdd = const ApiException(
      'GOAL_EXISTS',
      'You already have a goal for this exercise.',
    );

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await _setTarget(tester, '70');

    expect(
      find.text('You already have a goal for this exercise.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('goal.save')), findsOneWidget);
  });

  testWidgets('a lift found by search still knows your best', (tester) async {
    await _open(tester, results: [_summary(3, 'Bench Press')]);

    await _search(tester, 'ben');
    await tester.tap(find.byKey(const Key('goal.result.3')));
    await tester.pumpAndSettle();

    expect(find.text('Your best: 52.5 kg'), findsOneWidget);
  });

  testWidgets('back returns to the exercise list', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal.back')));
    await tester.pumpAndSettle();

    expect(find.text('LIFTED BEFORE'), findsOneWidget);
  });

  testWidgets('a sheet dismissed mid-save still refreshes the goals list', (
    tester,
  ) async {
    final completer = Completer<void>();
    final repo = _FakeGoalsRepo(const [_bench]);
    repo.blockAdd = completer;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          goalsRepositoryProvider.overrideWithValue(repo),
          weightUnitProvider.overrideWithValue(WeightUnit.kg),
          goalSearchProvider.overrideWith((ref, query) async => const []),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  final goals = ref.watch(goalsProvider);
                  return Column(
                    children: [
                      Text(
                        'Goals: ${goals.value?.length ?? 0}',
                        key: const Key('goal.count'),
                      ),
                      TextButton(
                        onPressed: () => showAddGoalSheet(context),
                        child: const Text('open'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Pick option, enter target, tap save.
    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal.target')), '60');
    await tester.tap(find.byKey(const Key('goal.save')));
    await tester.pump(); // Let the save start.

    // Dismiss the sheet while the save is in flight.
    Navigator.of(tester.element(find.byKey(const Key('goal.target')))).pop();
    await tester.pumpAndSettle();

    // Complete the add, which should refresh the goals list.
    completer.complete();
    await tester.pumpAndSettle();

    // The goals list should now show 1 goal, not 0.
    expect(find.text('Goals: 1'), findsOneWidget);
  });

  testWidgets('with the keyboard up the target field stays on screen', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);

    await _open(tester);
    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();

    // Should not have thrown an overflow exception.
    expect(tester.takeException(), isNull);

    // The target field should be on screen and hit-testable.
    final targetRect = tester.getRect(find.byKey(const Key('goal.target')));
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(targetRect.bottom, lessThanOrEqualTo(screenHeight - 300));
  });
}
