import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/routine/presentation/widgets/habit_sheet.dart';

const _dummyHabit = Habit(
  habitId: 99,
  title: 'placeholder',
  time: null,
  durationMin: null,
  weekdays: [1],
  done: false,
);

const _existing = Habit(
  habitId: 7,
  title: 'Run',
  time: '06:30',
  durationMin: 20,
  weekdays: [1, 3],
  done: false,
);

/// Records `add` / `edit` / `remove` calls, the model for a habit-sheet test's
/// fake per Task 5's `_FakeRepo`. `today()` is never actually awaited by the
/// sheet -- only the controller's write methods are -- but it is implemented
/// to satisfy the interface.
class _FakeRepo implements RoutineRepository {
  bool failNext = false;
  final added = <HabitDraft>[];
  final edited = <(int, HabitDraft)>[];
  final removed = <int>[];

  Future<void> _maybeFail() async {
    if (failNext) {
      failNext = false;
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
  }

  @override
  Future<RoutineDay> today() async =>
      const RoutineDay(date: '2026-09-21', habits: [], workout: null);

  @override
  Future<void> check(int habitId, {String? date}) => _maybeFail();
  @override
  Future<void> uncheck(int habitId, {String? date}) => _maybeFail();

  @override
  Future<Habit> add(HabitDraft draft) async {
    await _maybeFail();
    added.add(draft);
    return _dummyHabit;
  }

  @override
  Future<Habit> edit(int habitId, HabitDraft draft) async {
    await _maybeFail();
    edited.add((habitId, draft));
    return _dummyHabit;
  }

  @override
  Future<void> remove(int habitId) async {
    await _maybeFail();
    removed.add(habitId);
  }
}

Future<_FakeRepo> _open(
  WidgetTester tester, {
  Habit? existing,
  bool failNext = false,
}) async {
  final repo = _FakeRepo()..failNext = failNext;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showHabitSheet(context, existing: existing),
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

String _errorText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('habit.error'))).data!;

void main() {
  testWidgets('an empty title is rejected, shows why, and saves nothing', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(_errorText(tester), 'Give the habit a name.');
    expect(repo.added, isEmpty);
  });

  testWidgets('a title over 60 characters is rejected', (tester) async {
    final repo = await _open(tester);

    await tester.enterText(find.byKey(const Key('habit.title')), 'a' * 61);
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(_errorText(tester), 'Keep the name to 60 characters.');
    expect(repo.added, isEmpty);
  });

  testWidgets('a duration outside 1-600 minutes is rejected', (tester) async {
    final repo = await _open(tester);

    await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
    await tester.enterText(find.byKey(const Key('habit.duration')), '0');
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(_errorText(tester), 'Duration is 1 to 600 minutes.');
    expect(repo.added, isEmpty);
  });

  testWidgets('unticking every day is rejected', (tester) async {
    final repo = await _open(tester);
    await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');

    for (var weekday = 1; weekday <= 7; weekday += 1) {
      await tester.tap(find.byKey(Key('weekday.$weekday')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(_errorText(tester), 'Pick at least one day.');
    expect(repo.added, isEmpty);
  });

  testWidgets(
    'a valid new habit is added trimmed, with no time or duration, on every '
    'day, and the sheet closes',
    (tester) async {
      final repo = await _open(tester);

      await tester.enterText(
        find.byKey(const Key('habit.title')),
        '  Stretch  ',
      );
      await tester.tap(find.byKey(const Key('habit.save')));
      await tester.pumpAndSettle();

      final draft = repo.added.single;
      expect(draft.title, 'Stretch');
      expect(draft.time, isNull);
      expect(draft.durationMin, isNull);
      expect(draft.weekdays, [1, 2, 3, 4, 5, 6, 7]);
      expect(find.byKey(const Key('habit.save')), findsNothing);
    },
  );

  testWidgets('editing opens prefilled from the existing habit', (
    tester,
  ) async {
    await _open(tester, existing: _existing);

    expect(find.text('Run'), findsOneWidget);
    expect(find.text('6:30 AM'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.byKey(const Key('habit.delete')), findsOneWidget);
  });

  testWidgets('saving an edited habit calls edit with that habitId', (
    tester,
  ) async {
    final repo = await _open(tester, existing: _existing);

    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(repo.edited.single.$1, 7);
    expect(repo.edited.single.$2.title, 'Run');
    expect(find.byKey(const Key('habit.save')), findsNothing);
  });

  testWidgets('deleting calls remove with the habitId and closes the sheet', (
    tester,
  ) async {
    final repo = await _open(tester, existing: _existing);

    await tester.tap(find.byKey(const Key('habit.delete')));
    await tester.pumpAndSettle();

    expect(repo.removed, [7]);
    expect(find.byKey(const Key('habit.delete')), findsNothing);
  });

  testWidgets('a failed save keeps the sheet open and shows the error', (
    tester,
  ) async {
    await _open(tester, failNext: true);

    await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('habit.save')), findsOneWidget);
    expect(_errorText(tester), 'offline');
  });
}
