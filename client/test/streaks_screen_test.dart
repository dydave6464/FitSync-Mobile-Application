import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show weightUnitProvider;
import 'package:fitsync/features/streaks/data/streaks_repository.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart';
import 'package:fitsync/features/streaks/presentation/streaks_screen.dart';

/// Noon on Thursday 2026-09-24 in Manila.
DateTime _now() => DateTime.utc(2026, 9, 24, 4);

const _week = [
  StreakDay(date: '2026-09-21', active: true),
  StreakDay(date: '2026-09-22', active: false),
  StreakDay(date: '2026-09-23', active: true),
  StreakDay(date: '2026-09-24', active: true),
  StreakDay(date: '2026-09-25', active: false),
  StreakDay(date: '2026-09-26', active: false),
  StreakDay(date: '2026-09-27', active: false),
];

const _streak = Streak(current: 2, best: 5, todayActive: true, week: _week);

const _benchGoal = LiftGoal(
  goalId: 1,
  exerciseId: 3,
  exerciseName: 'Bench Press',
  targetKg: 60,
  bestKg: 52.5,
  reachedOn: null,
);

/// A goals list that can fail and records deletes.
class _FakeGoalsRepo implements GoalsRepository {
  _FakeGoalsRepo(List<LiftGoal> goals) : goals = [...goals];

  final List<LiftGoal> goals;
  final removed = <int>[];
  int failListTimes = 0;
  Completer<void>? _removeDelay;

  @override
  Future<List<LiftGoal>> list() async {
    if (failListTimes > 0) {
      failListTimes--;
      throw const ApiException('SERVER_ERROR', 'Goals broke.');
    }
    return List.of(goals);
  }

  @override
  Future<List<GoalOption>> options() async => const [];

  @override
  Future<LiftGoal> add({required int exerciseId, required double targetKg}) =>
      throw UnimplementedError();

  @override
  Future<void> remove(int goalId) async {
    if (_removeDelay != null) {
      await _removeDelay!.future;
    }
    removed.add(goalId);
    goals.removeWhere((g) => g.goalId == goalId);
  }
}

Future<_FakeGoalsRepo> _pump(
  WidgetTester tester, {
  Streak streak = _streak,
  Object? streakError,
  List<LiftGoal> goals = const [_benchGoal],
  int failGoals = 0,
}) async {
  final repo = _FakeGoalsRepo(goals)..failListTimes = failGoals;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        streakProvider.overrideWith((ref) async {
          if (streakError != null) throw streakError;
          return streak;
        }),
        goalsRepositoryProvider.overrideWithValue(repo),
        weightUnitProvider.overrideWithValue(WeightUnit.kg),
      ],
      child: const MaterialApp(home: StreaksScreen(now: _now)),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Finder _inDay(String date, Finder f) =>
    find.descendant(of: find.byKey(Key('streaks.day.$date')), matching: f);

void main() {
  testWidgets('the streak card shows the count, the best, and the week', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Streaks & goals'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('streaks.current'))).data,
      '2',
    );
    expect(find.text('Day streak · best 5'), findsOneWidget);
    expect(_inDay('2026-09-23', find.byIcon(Icons.check)), findsOneWidget);
    expect(_inDay('2026-09-22', find.byIcon(Icons.check)), findsNothing);
    final future = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const Key('streaks.day.2026-09-25')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(future.opacity, lessThan(1));
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
  });

  testWidgets('at zero it says how to start one', (tester) async {
    await _pump(
      tester,
      streak: const Streak(
        current: 0,
        best: 3,
        todayActive: false,
        week: _week,
      ),
    );

    expect(find.text('Day streak · best 3'), findsOneWidget);
    expect(
      find.text('Tick a habit or finish a workout to start one.'),
      findsOneWidget,
    );
  });

  testWidgets('with no best yet it reads just "Day streak"', (tester) async {
    await _pump(
      tester,
      streak: const Streak(
        current: 0,
        best: 0,
        todayActive: false,
        week: _week,
      ),
    );

    expect(find.text('Day streak'), findsOneWidget);
  });

  testWidgets('goal cards show progress, never logged, and reached', (
    tester,
  ) async {
    await _pump(
      tester,
      goals: const [
        _benchGoal,
        LiftGoal(
          goalId: 2,
          exerciseId: 4,
          exerciseName: 'Deadlift',
          targetKg: 100,
          bestKg: null,
          reachedOn: null,
        ),
        LiftGoal(
          goalId: 3,
          exerciseId: 5,
          exerciseName: 'Squat',
          targetKg: 80,
          bestKg: 82.5,
          reachedOn: '2026-09-12',
        ),
        LiftGoal(
          goalId: 4,
          exerciseId: 6,
          exerciseName: 'Row',
          targetKg: 50,
          bestKg: 55,
          reachedOn: '2025-12-30',
        ),
      ],
    );

    expect(find.text('52.5 / 60 kg'), findsOneWidget);
    expect(find.text('Not logged yet · 0 / 100 kg'), findsOneWidget);
    expect(find.text('Reached 12 Sep'), findsOneWidget);
    expect(find.text('Reached 30 Dec 2025'), findsOneWidget);
  });

  testWidgets('a goal can be deleted from its sheet', (tester) async {
    final repo = await _pump(tester);

    await tester.tap(find.byKey(const Key('streaks.goal.1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal.delete')));
    await tester.pumpAndSettle();

    expect(repo.removed, [1]);
    expect(find.byKey(const Key('streaks.goal.1')), findsNothing);
    expect(find.text('No goals yet'), findsOneWidget);
  });

  testWidgets('deletion completes even when sheet is dismissed during delete', (
    tester,
  ) async {
    final repo = await _pump(tester);
    final completer = Completer<void>();
    repo._removeDelay = completer;

    await tester.tap(find.byKey(const Key('streaks.goal.1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal.delete')));
    await tester.pump();

    // Dismiss the sheet by navigating away while delete is in progress
    // The container.invalidate should still work even after the widget is disposed
    final navContext = tester.element(find.byKey(const Key('goal.delete')));
    Navigator.of(navContext).pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // At this point sheet should be gone but delete still in progress
    expect(
      find.byKey(const Key('goal.delete')),
      findsNothing,
      reason: 'Sheet should be dismissed',
    );

    // Complete the delete
    completer.complete();
    await tester.pumpAndSettle();

    // Verify the goal was deleted from the repo and UI updated
    expect(repo.removed, [1]);
    expect(find.byKey(const Key('streaks.goal.1')), findsNothing);
    expect(find.text('No goals yet'), findsOneWidget);
  });

  testWidgets('with no goals it offers to add one', (tester) async {
    await _pump(tester, goals: const []);

    expect(find.text('No goals yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('streaks.goals.empty.add')));
    await tester.pumpAndSettle();

    expect(find.text('New goal'), findsOneWidget);
  });

  testWidgets('the + opens the add-goal sheet', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('streaks.goals.add')));
    await tester.pumpAndSettle();

    expect(find.text('New goal'), findsOneWidget);
  });

  testWidgets('a failed streak still shows the goals', (tester) async {
    await _pump(
      tester,
      streakError: const ApiException('SERVER_ERROR', 'Streak broke.'),
    );

    expect(find.byKey(const Key('streaks.streak.retry')), findsOneWidget);
    expect(find.byKey(const Key('streaks.goal.1')), findsOneWidget);
  });

  testWidgets('failed goals still show the streak, and Retry reloads them', (
    tester,
  ) async {
    await _pump(tester, failGoals: 1);

    expect(find.text('Day streak · best 5'), findsOneWidget);
    expect(find.byKey(const Key('streaks.goals.retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('streaks.goals.retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('streaks.goal.1')), findsOneWidget);
  });
}
