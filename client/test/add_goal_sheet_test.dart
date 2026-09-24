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

  @override
  Future<List<GoalOption>> options() async => _options;

  @override
  Future<List<LiftGoal>> list() async => const [];

  @override
  Future<LiftGoal> add({
    required int exerciseId,
    required double targetKg,
  }) async {
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

  testWidgets('an empty target asks for one', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await _setTarget(tester, '');

    expect(find.text('Enter a target weight.'), findsOneWidget);
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
}
