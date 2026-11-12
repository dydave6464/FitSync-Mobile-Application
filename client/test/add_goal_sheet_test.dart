import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_kit.dart' show FsRetry;
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
  _FakeGoalsRepo(this._options, {this.existing = const []});

  final List<GoalOption> _options;

  /// Goals the user already had before the sheet opened.
  final List<LiftGoal> existing;
  final added = <(int, double)>[];
  Object? failAdd;
  Completer<void>? blockAdd;

  /// How many loads of the lifted-before list fail before one works.
  int failOptionsTimes = 0;

  /// How many loads of the goals list fail before one works.
  int failListTimes = 0;
  int optionsCalls = 0;

  @override
  Future<List<GoalOption>> options() async {
    optionsCalls++;
    if (failOptionsTimes > 0) {
      failOptionsTimes--;
      throw const ApiException('SERVER_ERROR', 'Options broke.');
    }
    return _options;
  }

  @override
  Future<List<LiftGoal>> list() async {
    if (failListTimes > 0) {
      failListTimes--;
      throw const ApiException('SERVER_ERROR', 'Goals broke.');
    }
    // The goals already there, then the ones that were added.
    return [
      ...existing,
      ...added.map(
        (e) => LiftGoal(
          goalId: 1,
          exerciseId: e.$1,
          exerciseName: 'x',
          targetKg: e.$2,
          bestKg: null,
          reachedOn: null,
        ),
      ),
    ];
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
  Future<LiftGoal> changeTarget({
    required int goalId,
    required double targetKg,
  }) => throw UnimplementedError();

  @override
  Future<void> remove(int goalId) async {}
}

Future<_FakeGoalsRepo> _open(
  WidgetTester tester, {
  List<GoalOption> options = const [_bench],
  WeightUnit unit = WeightUnit.kg,
  List<ExerciseSummary> results = const [],
  List<LiftGoal> existing = const [],
  int failOptions = 0,
  int failList = 0,
}) async {
  final repo = _FakeGoalsRepo(options, existing: existing)
    ..failOptionsTimes = failOptions
    ..failListTimes = failList;
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
  // PT-22: the theme's handle is left off. Its 48 dp would push a sheet
  // sized to the room above the keyboard past the top of the screen, and a
  // drag on it would close the target step that back steps out of.
  testWidgets('takes the theme surface without Material\'s handle', (
    tester,
  ) async {
    await _open(tester);

    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
      isFalse,
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, FsTokens.light.surface);
  });

  testWidgets('lists what you have lifted, each with its best', (tester) async {
    await _open(tester);

    expect(find.text('New lift goal'), findsOneWidget);
    expect(find.text('LIFTED BEFORE'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Best 52.5 kg'), findsOneWidget);
  });

  testWidgets('with nothing lifted it points to search', (tester) async {
    await _open(tester, options: const []);

    expect(find.text('Search for an exercise to set a goal.'), findsOneWidget);
  });

  testWidgets('a lifted-before list that fails to load offers Try again', (
    tester,
  ) async {
    // It said why, but left no way to load it again short of closing the
    // sheet.
    await _open(tester, failOptions: 1);

    expect(find.byType(FsRetry), findsOneWidget);
    expect(
      find.text(
        userMessage(const ApiException('SERVER_ERROR', 'Options broke.')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('goal.options.retry')));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
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

  testWidgets('a validation error is spoken when it appears', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await _setTarget(tester, '');

    expect(
      tester.getSemantics(find.byKey(const Key('goal.error'))),
      matchesSemantics(label: 'Enter a target weight.', isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('a server refusal is spoken when it appears', (tester) async {
    final handle = tester.ensureSemantics();
    final repo = await _open(tester);
    repo.failAdd = const ApiException(
      'GOAL_EXISTS',
      'You already have a goal for this exercise.',
    );

    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await _setTarget(tester, '70');

    expect(
      tester.getSemantics(find.byKey(const Key('goal.error'))),
      matchesSemantics(
        label: 'You already have a goal for this exercise.',
        isLiveRegion: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the target keeps its unit beside it once a value is typed', (
    tester,
  ) async {
    // The unit lived only in the hint, which goes as soon as you type.
    await _open(tester, unit: WeightUnit.lb);
    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal.target')), '135');
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('goal.target')),
    );
    expect(field.decoration!.suffixText, 'lb');
    expect(field.decoration!.hintText, 'Target');
  });

  testWidgets('each exercise row is a 48 dp button', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, results: [_summary(8, 'Deadlift')]);

    await _search(tester, 'dead');
    final row = find.byKey(const Key('goal.result.8'));
    // A search result has no subtitle, the shortest row there is.
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(row),
      matchesSemantics(
        label: 'Deadlift',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets("the phone's back on the target step returns to the list, "
      'keeping the sheet open', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('New lift goal'), findsOneWidget);
    expect(find.text('LIFTED BEFORE'), findsOneWidget);

    // From the list, back closes the sheet as before.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('New lift goal'), findsNothing);
  });

  testWidgets('a tap outside the sheet on the target step closes it, as a '
      'drag down does, rather than stepping back', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('goal.option.3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal.target')), findsOneWidget);

    // The scrim above the sheet.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('New lift goal'), findsNothing);
  });

  testWidgets('the scrim still reads as dismissible to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester);

    final scrim = find.bySemanticsLabel('Scrim');
    expect(scrim, findsOneWidget);
    expect(
      tester
          .getSemantics(scrim)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('a search that fails offers Try again, which searches again', (
    tester,
  ) async {
    var calls = 0;
    final repo = _FakeGoalsRepo(const [_bench]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          goalsRepositoryProvider.overrideWithValue(repo),
          weightUnitProvider.overrideWithValue(WeightUnit.kg),
          goalSearchProvider.overrideWith((ref, query) async {
            calls += 1;
            if (calls == 1) {
              throw const ApiException('SERVER_ERROR', 'Search broke.');
            }
            return [_summary(8, 'Deadlift')];
          }),
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

    await _search(tester, 'dead');

    expect(
      find.text(
        userMessage(const ApiException('SERVER_ERROR', 'Search broke.')),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('goal.search.retry')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Deadlift'), findsOneWidget);
  });

  group('a lift that already has a goal', () {
    const openBench = LiftGoal(
      goalId: 9,
      exerciseId: 3,
      exerciseName: 'Bench Press',
      targetKg: 60,
      bestKg: 52.5,
      reachedOn: null,
    );

    testWidgets('is tagged in the list and opens its goal, not a new one', (
      tester,
    ) async {
      // Offered as if new, it failed only after the target was typed and
      // saved ("You already have a goal for this exercise").
      final repo = await _open(tester, existing: const [openBench]);

      final row = find.byKey(const Key('goal.option.3'));
      expect(
        find.descendant(of: row, matching: find.text('Goal set')),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('goal.target')), findsNothing);
      expect(
        find.text('New lift goal'),
        findsNothing,
        reason: 'add sheet closed',
      );
      expect(find.text('Target 60 kg'), findsOneWidget);
      expect(find.byKey(const Key('goal.delete')), findsOneWidget);
      expect(repo.added, isEmpty);
    });

    testWidgets('is tagged in search results too', (tester) async {
      await _open(
        tester,
        existing: const [openBench],
        results: [_summary(3, 'Bench Press'), _summary(8, 'Deadlift')],
      );

      await _search(tester, 'e');
      expect(
        find.descendant(
          of: find.byKey(const Key('goal.result.3')),
          matching: find.text('Goal set'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('goal.result.8')),
          matching: find.text('Goal set'),
        ),
        findsNothing,
      );
    });

    testWidgets('a reached goal does not count: the lift can take a new one', (
      tester,
    ) async {
      await _open(
        tester,
        existing: const [
          LiftGoal(
            goalId: 9,
            exerciseId: 3,
            exerciseName: 'Bench Press',
            targetKg: 50,
            bestKg: 52.5,
            reachedOn: '2026-09-01',
          ),
        ],
      );

      expect(find.text('Goal set'), findsNothing);
      await tester.tap(find.byKey(const Key('goal.option.3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('goal.target')), findsOneWidget);
    });
  });

  group('when the goals list could not say', () {
    const openBench = LiftGoal(
      goalId: 9,
      exerciseId: 3,
      exerciseName: 'Bench Press',
      targetKg: 60,
      bestKg: 52.5,
      reachedOn: null,
    );
    const markedBench = GoalOption(
      exerciseId: 3,
      name: 'Bench Press',
      bestKg: 52.5,
      sets: 6,
      hasOpenGoal: true,
      goalId: 9,
    );

    testWidgets("the options' own mark still tags the row", (tester) async {
      await _open(tester, options: const [markedBench], failList: 1);

      expect(
        find.descendant(
          of: find.byKey(const Key('goal.option.3')),
          matching: find.text('Goal set'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a marked row reloads the goals and opens its goal', (
      tester,
    ) async {
      final repo = await _open(
        tester,
        options: const [markedBench],
        existing: const [openBench],
        failList: 1,
      );

      await tester.tap(find.byKey(const Key('goal.option.3')));
      await tester.pumpAndSettle();

      expect(find.text('New lift goal'), findsNothing);
      expect(find.byKey(const Key('goal.target')), findsNothing);
      expect(find.text('Target 60 kg'), findsOneWidget);
      expect(repo.added, isEmpty);
    });

    testWidgets('a marked row whose goal cannot be found goes to step two', (
      tester,
    ) async {
      await _open(tester, options: const [markedBench], failList: 2);

      await tester.tap(find.byKey(const Key('goal.option.3')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('goal.target')), findsOneWidget);
    });

    const deadliftGoal = LiftGoal(
      goalId: 12,
      exerciseId: 8,
      exerciseName: 'Deadlift',
      targetKg: 120,
      bestKg: 100,
      reachedOn: null,
    );
    const exists = ApiException(
      'GOAL_EXISTS',
      'You already have a goal for this exercise.',
      details: [
        {'field': 'exerciseId', 'goalId': 12},
      ],
    );

    testWidgets("a save refused as GOAL_EXISTS opens that goal's sheet", (
      tester,
    ) async {
      final repo = await _open(
        tester,
        results: [_summary(8, 'Deadlift')],
        existing: const [deadliftGoal],
        failList: 1,
      );
      repo.failAdd = exists;

      await _search(tester, 'dead');
      await tester.tap(find.byKey(const Key('goal.result.8')));
      await tester.pumpAndSettle();
      await _setTarget(tester, '130');

      expect(find.text('New lift goal'), findsNothing);
      expect(find.byKey(const Key('goal.target')), findsNothing);
      expect(find.text('Target 120 kg'), findsOneWidget);
      expect(find.byKey(const Key('goal.delete')), findsOneWidget);
    });

    testWidgets('a GOAL_EXISTS whose goal cannot be found says so', (
      tester,
    ) async {
      final repo = await _open(
        tester,
        results: [_summary(8, 'Deadlift')],
        failList: 1,
      );
      repo.failAdd = exists;

      await _search(tester, 'dead');
      await tester.tap(find.byKey(const Key('goal.result.8')));
      await tester.pumpAndSettle();
      await _setTarget(tester, '130');

      expect(
        find.descendant(
          of: find.byKey(const Key('goal.error')),
          matching: find.text('You already have a goal for this exercise.'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('goal.save')), findsOneWidget);
    });
  });

  group("the server's best, when the sheet did not know it", () {
    testWidgets("is said in the user's unit and updates the best line", (
      tester,
    ) async {
      final repo = await _open(
        tester,
        unit: WeightUnit.lb,
        results: [_summary(8, 'Deadlift')],
      );
      repo.failAdd = const ApiException(
        'GOAL_ALREADY_MET',
        'Your best is already 60 kg.',
        details: [
          {'field': 'targetKg', 'bestKg': 60},
        ],
      );

      await _search(tester, 'dead');
      await tester.tap(find.byKey(const Key('goal.result.8')));
      await tester.pumpAndSettle();
      expect(find.text('Not logged yet'), findsOneWidget);
      final optionsBefore = repo.optionsCalls;
      await _setTarget(tester, '120');

      expect(
        find.text(
          'Your best is already ${formatWeightWithUnit(60, WeightUnit.lb)}.',
        ),
        findsOneWidget,
      );
      expect(find.text('Your best is already 132.3 lb.'), findsOneWidget);
      expect(find.text('Your best: 132.3 lb'), findsOneWidget);
      expect(repo.optionsCalls, greaterThan(optionsBefore));
    });

    testWidgets("without the numbers the server's sentence is shown", (
      tester,
    ) async {
      final repo = await _open(
        tester,
        unit: WeightUnit.lb,
        results: [_summary(8, 'Deadlift')],
      );
      repo.failAdd = const ApiException(
        'GOAL_ALREADY_MET',
        'Your best is already 60 kg.',
      );

      await _search(tester, 'dead');
      await tester.tap(find.byKey(const Key('goal.result.8')));
      await tester.pumpAndSettle();
      await _setTarget(tester, '120');

      expect(find.text('Your best is already 60 kg.'), findsOneWidget);
      expect(find.text('Not logged yet'), findsOneWidget);
    });
  });
}
