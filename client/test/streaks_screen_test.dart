import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart' show FsCard, FsRetry;
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show weightUnitProvider;
import 'package:fitsync/features/streaks/data/streaks_repository.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart';
import 'package:fitsync/features/streaks/presentation/streaks_screen.dart';

import 'helpers/a11y.dart' show contrast;

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

  final added = <(int, double)>[];

  /// Makes every add throw it.
  Object? failAdd;

  @override
  Future<LiftGoal> add({
    required int exerciseId,
    required double targetKg,
  }) async {
    if (failAdd != null) throw failAdd!;
    added.add((exerciseId, targetKg));
    final goal = LiftGoal(
      goalId: 100 + added.length,
      exerciseId: exerciseId,
      exerciseName: 'Bench Press',
      targetKg: targetKg,
      bestKg: 52.5,
      reachedOn: null,
    );
    goals.add(goal);
    return goal;
  }

  /// Makes every remove throw it.
  Object? failRemove;

  @override
  Future<void> remove(int goalId) async {
    if (failRemove != null) throw failRemove!;
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
  bool dark = false,
  double textScale = 1.0,
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
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        home: const StreaksScreen(now: _now),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Finder _inDay(String date, Finder f) =>
    find.descendant(of: find.byKey(Key('streaks.day.$date')), matching: f);

/// The product of every [Opacity] above [finder].
double _opacityOver(WidgetTester tester, Finder finder) => tester
    .widgetList<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)),
    )
    .fold(1.0, (a, o) => a * o.opacity);

/// FsCard(accent: true) where its tint is strongest: accent at 0.16 over
/// the page.
Color _strongestTint(FsTokens t) =>
    Color.alphaBlend(t.accent.withValues(alpha: 0.16), t.bg);

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

  group('deleting a goal can be taken back', () {
    Future<void> deleteBench(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('streaks.goal.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('goal.delete')));
      await tester.pumpAndSettle();
    }

    testWidgets('an open goal goes at once, with Undo to put it back', (
      tester,
    ) async {
      // One tap deleted it for good, and a target could only be changed by
      // deleting, searching, picking and retyping.
      final repo = await _pump(tester);
      await deleteBench(tester);

      expect(repo.removed, [1]);
      expect(find.text('Goal deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(repo.added, [(3, 60.0)]);
      expect(find.text('52.5 / 60 kg'), findsOneWidget);
    });

    testWidgets('an Undo that fails says why', (tester) async {
      final repo = await _pump(tester);
      repo.failAdd = const ApiException('NETWORK_ERROR', 'offline');
      await deleteBench(tester);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(repo.added, isEmpty);
      expect(find.text(userMessage(repo.failAdd!)), findsOneWidget);
    });

    testWidgets('a reached goal asks first, since it cannot be set again', (
      tester,
    ) async {
      const squat = LiftGoal(
        goalId: 3,
        exerciseId: 5,
        exerciseName: 'Squat',
        targetKg: 80,
        bestKg: 82.5,
        reachedOn: '2026-09-12',
      );
      final repo = await _pump(tester, goals: const [squat]);

      await tester.tap(find.byKey(const Key('streaks.goal.3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('goal.delete')));
      await tester.pumpAndSettle();

      expect(find.text('Delete this goal?'), findsOneWidget);
      expect(repo.removed, isEmpty, reason: 'asking is not doing');

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(repo.removed, isEmpty);
      expect(find.byKey(const Key('goal.delete')), findsOneWidget);

      await tester.tap(find.byKey(const Key('goal.delete')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.removed, [3]);
      expect(find.text('Undo'), findsNothing);
    });
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
    // The app's shared retry treatment.
    expect(find.byType(FsRetry), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
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

  for (final dark in [false, true]) {
    testWidgets('the later days\' letters read at 4.5:1 on the streak card '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(tester, dark: dark);
      final t = dark ? FsTokens.dark : FsTokens.light;

      // Friday, a day still to come (the clock is Thursday).
      final letter = find.text('F');
      final color = tester.widget<Text>(letter).style!.color!;
      final shown = color.withValues(
        alpha: color.a * _opacityOver(tester, letter),
      );

      expect(contrast(shown, _strongestTint(t)), greaterThanOrEqualTo(4.5));
      // The circle itself is still dimmed, as the design shows.
      expect(
        _opacityOver(tester, find.byKey(const Key('streaks.day.2026-09-25'))),
        lessThan(1),
      );
    });
  }

  testWidgets('a screen reader hears each day of the week with its state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(
      find.bySemanticsLabel(
        'This week: Monday, done; Tuesday, missed; Wednesday, done; '
        'Thursday, today, done; Friday, not yet; Saturday, not yet; '
        'Sunday, not yet',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('M'),
      findsNothing,
      reason: 'the bare letters are replaced by the sentence',
    );
    handle.dispose();
  });

  testWidgets('today not yet active reads as "today, not yet"', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      streak: const Streak(
        current: 1,
        best: 1,
        todayActive: false,
        week: [
          StreakDay(date: '2026-09-21', active: false),
          StreakDay(date: '2026-09-22', active: false),
          StreakDay(date: '2026-09-23', active: true),
          StreakDay(date: '2026-09-24', active: false),
          StreakDay(date: '2026-09-25', active: false),
          StreakDay(date: '2026-09-26', active: false),
          StreakDay(date: '2026-09-27', active: false),
        ],
      ),
    );

    expect(
      find.bySemanticsLabel(RegExp('Thursday, today, not yet;')),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets('a goal\'s bar reads at 3:1 on its card '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(tester, dark: dark);
      final t = dark ? FsTokens.dark : FsTokens.light;
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byKey(const Key('streaks.goal.1')),
          matching: find.byType(LinearProgressIndicator),
        ),
      );

      expect(contrast(bar.color!, t.surface), greaterThanOrEqualTo(3));
    });
  }

  testWidgets('a failed delete is spoken and keeps the sheet open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repo = await _pump(tester);
    repo.failRemove = const ApiException('SERVER_ERROR', 'Could not delete.');

    await tester.tap(find.byKey(const Key('streaks.goal.1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal.delete')));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byKey(const Key('goal.deleteError'))),
      matchesSemantics(label: 'Could not delete.', isLiveRegion: true),
    );
    expect(find.byKey(const Key('goal.delete')), findsOneWidget);
    handle.dispose();
  });

  // A done day's dot is data, read for whether it is filled: accentFill,
  // which holds 3:1 on the card's tint where the brand green (about 2.4:1
  // there in light) does not.
  for (final dark in [false, true]) {
    testWidgets("a done day's dot is filled in accentFill "
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(tester, dark: dark);
      final t = dark ? FsTokens.dark : FsTokens.light;
      final key = find.byKey(const Key('streaks.day.2026-09-23'));
      final fill =
          (tester.widget<Container>(key).decoration! as BoxDecoration).color!;
      expect(fill, t.accentFill);

      // The card's tint where the dot sits: FsCard(accent: true) fades from
      // accent at 0.16 (top left) to 0.03 (bottom right).
      final card = tester.getRect(
        find.ancestor(of: key, matching: find.byType(FsCard)).first,
      );
      final at = tester.getCenter(key) - card.topLeft;
      final along =
          ((at.dx * card.width + at.dy * card.height) /
                  (card.width * card.width + card.height * card.height))
              .clamp(0.0, 1.0);
      final tint = Color.alphaBlend(
        t.accent.withValues(alpha: 0.16 + (0.03 - 0.16) * along),
        t.bg,
      );
      expect(contrast(fill, tint), greaterThanOrEqualTo(3));
    });
  }
}
