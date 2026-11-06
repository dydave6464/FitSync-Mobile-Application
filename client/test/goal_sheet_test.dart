import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/streaks/data/streaks_repository.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/goal_sheet.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart';

const _bench = LiftGoal(
  goalId: 1,
  exerciseId: 3,
  exerciseName: 'Bench Press',
  targetKg: 60,
  bestKg: 52.5,
  reachedOn: null,
);

const _reachedSquat = LiftGoal(
  goalId: 2,
  exerciseId: 5,
  exerciseName: 'Squat',
  targetKg: 80,
  bestKg: 82.5,
  reachedOn: '2026-09-12',
);

/// Records target changes and counts loads of the goals list.
class _FakeGoalsRepo implements GoalsRepository {
  _FakeGoalsRepo(this.goal);

  final LiftGoal goal;
  final changed = <(int, double)>[];
  Object? failChange;
  int listCalls = 0;

  @override
  Future<List<LiftGoal>> list() async {
    listCalls++;
    return [goal];
  }

  @override
  Future<List<GoalOption>> options() async => const [];

  @override
  Future<LiftGoal> add({required int exerciseId, required double targetKg}) =>
      throw UnimplementedError();

  @override
  Future<LiftGoal> changeTarget({
    required int goalId,
    required double targetKg,
  }) async {
    if (failChange != null) throw failChange!;
    changed.add((goalId, targetKg));
    return LiftGoal(
      goalId: goalId,
      exerciseId: goal.exerciseId,
      exerciseName: goal.exerciseName,
      targetKg: targetKg,
      bestKg: goal.bestKg,
      reachedOn: null,
    );
  }

  @override
  Future<void> remove(int goalId) async {}
}

Future<_FakeGoalsRepo> _open(
  WidgetTester tester, {
  LiftGoal goal = _bench,
  WeightUnit unit = WeightUnit.kg,
  double textScale = 1.0,
}) async {
  final repo = _FakeGoalsRepo(goal);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [goalsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // Keeps the goals list alive, as the streaks screen does.
              ref.watch(goalsProvider);
              return TextButton(
                onPressed: () => showGoalSheet(context, goal, unit),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _edit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('goal.changeTarget')));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String? text) async {
  if (text != null) {
    await tester.enterText(find.byKey(const Key('goal.edit.target')), text);
  }
  await tester.tap(find.byKey(const Key('goal.edit.save')));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('goal.edit.target')))
    .controller!
    .text;

void main() {
  testWidgets('an open goal offers Change target above Delete', (tester) async {
    await _open(tester);

    final change = find.byKey(const Key('goal.changeTarget'));
    expect(change, findsOneWidget);
    expect(find.text('Change target'), findsOneWidget);
    expect(
      tester.getRect(change).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('goal.delete'))).top,
      ),
    );
  });

  testWidgets('a reached goal does not, as the server refuses it', (
    tester,
  ) async {
    await _open(tester, goal: _reachedSquat);

    expect(find.byKey(const Key('goal.changeTarget')), findsNothing);
    expect(find.byKey(const Key('goal.delete')), findsOneWidget);
  });

  testWidgets('the sheet has no drag handle and sizes for the keyboard', (
    tester,
  ) async {
    // PT-22, as the add-goal sheet.
    await _open(tester);

    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.showDragHandle, isFalse);
  });

  testWidgets('the edit step shows the lift, the best and the target', (
    tester,
  ) async {
    await _open(tester);
    await _edit(tester);

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Your best: 52.5 kg'), findsOneWidget);
    expect(_fieldText(tester), '60');
    final field = tester.widget<TextField>(
      find.byKey(const Key('goal.edit.target')),
    );
    expect(field.decoration!.suffixText, 'kg');
    expect(field.decoration!.hintText, 'Target');
    expect(find.byKey(const Key('goal.delete')), findsNothing);
  });

  testWidgets('a lift never logged says so on the edit step', (tester) async {
    await _open(
      tester,
      goal: const LiftGoal(
        goalId: 4,
        exerciseId: 8,
        exerciseName: 'Deadlift',
        targetKg: 100,
        bestKg: null,
        reachedOn: null,
      ),
    );
    await _edit(tester);

    expect(find.text('Not logged yet'), findsOneWidget);
  });

  testWidgets('the target is prefilled in pounds for a pound user', (
    tester,
  ) async {
    await _open(
      tester,
      goal: const LiftGoal(
        goalId: 1,
        exerciseId: 3,
        exerciseName: 'Bench Press',
        targetKg: 100,
        bestKg: 52.5,
        reachedOn: null,
      ),
      unit: WeightUnit.lb,
    );
    await _edit(tester);

    expect(_fieldText(tester), formatWeight(100, WeightUnit.lb));
    expect(_fieldText(tester), '220.5');
    expect(find.text('Your best: 115.7 lb'), findsOneWidget);
  });

  testWidgets('Save sends kilograms, closes and says the target changed', (
    tester,
  ) async {
    final repo = await _open(tester);
    final loads = repo.listCalls;
    await _edit(tester);
    await _save(tester, '70');

    expect(repo.changed, [(1, 70.0)]);
    expect(find.byKey(const Key('goal.edit.save')), findsNothing);
    expect(find.text('Target changed'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(repo.listCalls, greaterThan(loads), reason: 'goals refreshed');
  });

  testWidgets('a pound target is sent in kilograms', (tester) async {
    final repo = await _open(tester, unit: WeightUnit.lb);
    await _edit(tester);
    await _save(tester, '135');

    expect(repo.changed.single.$1, 1);
    expect(repo.changed.single.$2, closeTo(61.23, 0.0001));
  });

  testWidgets('an unchanged target closes with no request', (tester) async {
    // 100 kg shows as 220.5 lb, which is 100.02 kg: saving it as typed
    // would move the target.
    final repo = await _open(
      tester,
      goal: const LiftGoal(
        goalId: 1,
        exerciseId: 3,
        exerciseName: 'Bench Press',
        targetKg: 100,
        bestKg: 52.5,
        reachedOn: null,
      ),
      unit: WeightUnit.lb,
    );
    await _edit(tester);
    await _save(tester, null);

    expect(repo.changed, isEmpty);
    expect(find.byKey(const Key('goal.edit.save')), findsNothing);
    expect(find.text('Target changed'), findsNothing);
  });

  testWidgets('a target at or below the best is refused in the sheet', (
    tester,
  ) async {
    final repo = await _open(tester);
    await _edit(tester);
    await _save(tester, '52.5');

    expect(
      find.descendant(
        of: find.byKey(const Key('goal.edit.error')),
        matching: find.text('Your best is already 52.5 kg.'),
      ),
      findsOneWidget,
    );
    expect(repo.changed, isEmpty);
    expect(find.byKey(const Key('goal.edit.save')), findsOneWidget);
  });

  testWidgets('an empty target asks for one', (tester) async {
    final repo = await _open(tester);
    await _edit(tester);
    await _save(tester, '');

    expect(find.text('Enter a target weight.'), findsOneWidget);
    expect(repo.changed, isEmpty);
  });

  testWidgets('a reached goal refused by the server says so and refreshes', (
    tester,
  ) async {
    final repo = await _open(tester);
    repo.failChange = const ApiException(
      'GOAL_REACHED',
      "You've reached this goal. Add a new one to aim higher.",
    );
    final loads = repo.listCalls;
    await _edit(tester);
    await _save(tester, '70');

    expect(
      find.descendant(
        of: find.byKey(const Key('goal.edit.error')),
        matching: find.text(
          "You've reached this goal. Add a new one to aim higher.",
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('goal.edit.save')), findsOneWidget);
    expect(repo.listCalls, greaterThan(loads), reason: 'goals refreshed');
  });

  testWidgets('a goal gone from the server says so and refreshes', (
    tester,
  ) async {
    final repo = await _open(tester);
    repo.failChange = const ApiException('GOAL_NOT_FOUND', 'No such goal.');
    final loads = repo.listCalls;
    await _edit(tester);
    await _save(tester, '70');

    expect(find.text('No such goal.'), findsOneWidget);
    expect(repo.listCalls, greaterThan(loads));
  });

  testWidgets("the server's best is said in the user's unit", (tester) async {
    final repo = await _open(tester, unit: WeightUnit.lb);
    repo.failChange = const ApiException(
      'GOAL_ALREADY_MET',
      'Your best is already 60 kg.',
      details: [
        {'field': 'targetKg', 'bestKg': 60},
      ],
    );
    await _edit(tester);
    await _save(tester, '135');

    expect(find.text('Your best is already 132.3 lb.'), findsOneWidget);
    expect(find.text('Your best: 132.3 lb'), findsOneWidget);
    expect(find.byKey(const Key('goal.edit.save')), findsOneWidget);
  });

  testWidgets('any other failure is said plainly and keeps the step', (
    tester,
  ) async {
    final repo = await _open(tester);
    repo.failChange = const ApiException('NETWORK_ERROR', 'host down');
    await _edit(tester);
    await _save(tester, '70');

    expect(find.text(userMessage(repo.failChange!)), findsOneWidget);
    expect(find.byKey(const Key('goal.edit.target')), findsOneWidget);
  });

  testWidgets('the back arrow returns to the goal', (tester) async {
    await _open(tester);
    await _edit(tester);

    await tester.tap(find.byKey(const Key('goal.edit.back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goal.edit.target')), findsNothing);
    expect(find.byKey(const Key('goal.changeTarget')), findsOneWidget);
  });

  testWidgets("the phone's back on the edit step returns to the goal, "
      'and from there closes the sheet', (tester) async {
    await _open(tester);
    await _edit(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal.edit.target')), findsNothing);
    expect(find.byKey(const Key('goal.changeTarget')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a tap outside the sheet on the edit step closes it', (
    tester,
  ) async {
    await _open(tester);
    await _edit(tester);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
  });

  for (final size in const [Size(360, 640), Size(320, 568)]) {
    testWidgets('at 2x text on ${size.width.toInt()} dp with the keyboard up '
        'the edit step fits and its field stays on screen', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _open(tester, textScale: 2.0);
      expect(tester.takeException(), isNull);
      await _edit(tester);
      // The keyboard comes up as the field is tapped.
      await tester.tap(find.byKey(const Key('goal.edit.target')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final field = tester.getRect(find.byKey(const Key('goal.edit.target')));
      expect(field.top, greaterThanOrEqualTo(0));
      expect(field.bottom, lessThanOrEqualTo(size.height - 280));

      // Save is there, scrolled to if need be.
      await tester.ensureVisible(find.byKey(const Key('goal.edit.save')));
      await tester.pumpAndSettle();
      final save = tester.getRect(find.byKey(const Key('goal.edit.save')));
      expect(save.bottom, lessThanOrEqualTo(size.height - 280));
    });
  }

  testWidgets('a validation error is spoken when it appears', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);
    await _edit(tester);
    await _save(tester, '');

    expect(
      tester.getSemantics(find.byKey(const Key('goal.edit.error'))),
      matchesSemantics(label: 'Enter a target weight.', isLiveRegion: true),
    );
    handle.dispose();
  });
}
