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
/// fake per Task 5's `_FakeRepo`. `today()` answers the harness's first load
/// and each write's reload, from [days].
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

  /// The day each successive `today()` answers with; the last repeats. More
  /// than one simulates midnight passing while the sheet is open.
  List<String> days = const ['2026-09-21'];
  int _todayCalls = 0;

  @override
  Future<RoutineDay> today() async => RoutineDay(
    date: days[(_todayCalls++).clamp(0, days.length - 1)],
    habits: const [],
    workout: null,
  );

  @override
  Future<void> check(int habitId, {String? date}) => _maybeFail();
  @override
  Future<void> uncheck(int habitId, {String? date}) => _maybeFail();

  /// Echoes the draft back as the saved habit -- what the real server does --
  /// so a test can tell what the sheet was told was saved, weekdays included.
  Habit _fromDraft(int habitId, HabitDraft draft) => Habit(
    habitId: habitId,
    title: draft.title,
    time: draft.time,
    durationMin: draft.durationMin,
    weekdays: draft.weekdays,
    done: false,
  );

  @override
  Future<Habit> add(HabitDraft draft) async {
    await _maybeFail();
    added.add(draft);
    return _fromDraft(_dummyHabit.habitId, draft);
  }

  @override
  Future<Habit> edit(int habitId, HabitDraft draft) async {
    await _maybeFail();
    edited.add((habitId, draft));
    return _fromDraft(habitId, draft);
  }

  @override
  Future<void> remove(int habitId) async {
    await _maybeFail();
    removed.add(habitId);
  }

  @override
  Future<List<Habit>> all() async => const [];
}

Future<_FakeRepo> _open(
  WidgetTester tester, {
  Habit? existing,
  bool failNext = false,
  List<String>? days,
}) async {
  final repo = _FakeRepo()..failNext = failNext;
  if (days != null) repo.days = days;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: fsLightTheme(),
        // Watches the day, as the routine screen and Home's card do: the
        // sheet is only ever opened over a routine that has loaded.
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(routineTodayProvider);
            return Scaffold(
              body: TextButton(
                onPressed: () => showHabitSheet(context, existing: existing),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

  testWidgets(
    'saving a habit that does not repeat today says what days it repeats on',
    (tester) async {
      await _open(tester);

      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      // The fixture day (2026-09-21) is a Monday: weekday 1. Leave only
      // Tuesday (2) and Thursday (4) selected, so today is excluded.
      for (final weekday in [1, 3, 5, 6, 7]) {
        await tester.tap(find.byKey(Key('weekday.$weekday')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('habit.save')));
      await tester.pumpAndSettle();

      expect(find.text('Saved — repeats Tue, Thu'), findsOneWidget);
    },
  );

  testWidgets(
    'a save that lands after midnight still compares against the day it opened on',
    (tester) async {
      // Opened on Monday 2026-09-21; the save's own reload comes back on
      // Tuesday. A Tuesday-only habit does not repeat on the day the person
      // was looking at, so they are told when it does.
      await _open(tester, days: ['2026-09-21', '2026-09-22']);

      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      for (final weekday in [1, 3, 4, 5, 6, 7]) {
        await tester.tap(find.byKey(Key('weekday.$weekday')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('habit.save')));
      await tester.pumpAndSettle();

      expect(find.text('Saved — repeats Tue'), findsOneWidget);
    },
  );

  testWidgets(
    'saving a habit that does repeat today shows no repeats snackbar',
    (tester) async {
      await _open(tester);

      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      await tester.tap(find.byKey(const Key('habit.save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('repeats'), findsNothing);
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
