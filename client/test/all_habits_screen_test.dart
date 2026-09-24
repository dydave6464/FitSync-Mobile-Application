import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/all_habits_screen.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';

const _stretch = Habit(
  habitId: 4,
  title: 'Stretch',
  time: '21:00',
  durationMin: 10,
  weekdays: [1, 3, 5],
  done: false,
);

const _walk = Habit(
  habitId: 5,
  title: 'Walk',
  time: null,
  durationMin: null,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  done: false,
);

/// A server in miniature: `all()` answers from [habits], and add/edit/remove
/// change it, so a refetch after a write shows the write.
class _FakeRepo implements RoutineRepository {
  _FakeRepo(List<Habit> habits) : habits = [...habits];

  final List<Habit> habits;
  int failAllTimes = 0;
  int allCalls = 0;
  int _nextId = 100;

  @override
  Future<List<Habit>> all() async {
    allCalls++;
    if (failAllTimes > 0) {
      failAllTimes--;
      throw const ApiException('SERVER_ERROR', 'Something broke.');
    }
    return List.of(habits);
  }

  /// Monday, so a Tuesday/Thursday habit saved from a sheet that announces
  /// repeats would announce them.
  @override
  Future<RoutineDay> today() async =>
      const RoutineDay(date: '2026-09-21', habits: [], workout: null);

  Habit _fromDraft(int id, HabitDraft d) => Habit(
    habitId: id,
    title: d.title,
    time: d.time,
    durationMin: d.durationMin,
    weekdays: d.weekdays,
    done: false,
  );

  @override
  Future<Habit> add(HabitDraft draft) async {
    final h = _fromDraft(_nextId++, draft);
    habits.add(h);
    return h;
  }

  @override
  Future<Habit> edit(int habitId, HabitDraft draft) async {
    final h = _fromDraft(habitId, draft);
    habits[habits.indexWhere((x) => x.habitId == habitId)] = h;
    return h;
  }

  @override
  Future<void> remove(int habitId) async =>
      habits.removeWhere((x) => x.habitId == habitId);

  @override
  Future<void> check(int habitId, {String? date}) async {}
  @override
  Future<void> uncheck(int habitId, {String? date}) async {}
}

/// Pumps the screen over a loaded routine day, as in the app, where it is
/// pushed from the Daily Routine screen.
Future<_FakeRepo> _pump(WidgetTester tester, List<Habit> habits) async {
  final repo = _FakeRepo(habits);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(routineTodayProvider);
            return const AllHabitsScreen();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

void main() {
  testWidgets('each row shows its days, then its time and duration', (
    tester,
  ) async {
    await _pump(tester, [_stretch, _walk]);

    expect(find.text('All habits'), findsOneWidget);
    expect(find.text('Mon, Wed, Fri · 9:00 PM · 10 min'), findsOneWidget);
    // Untimed, no duration, all seven days: only the days.
    expect(find.text('Every day'), findsOneWidget);
  });

  testWidgets('tapping a row opens the sheet to edit that habit', (
    tester,
  ) async {
    await _pump(tester, [_stretch, _walk]);

    await tester.tap(find.byKey(const Key('allHabits.habit.4')));
    await tester.pumpAndSettle();

    expect(_inSheet(find.text('Edit habit')), findsOneWidget);
    expect(_inSheet(find.text('Stretch')), findsOneWidget);
    expect(find.byKey(const Key('habit.delete')), findsOneWidget);
  });

  testWidgets('an edit shows in the list once saved', (tester) async {
    await _pump(tester, [_stretch]);

    await tester.tap(find.byKey(const Key('allHabits.habit.4')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('habit.title')),
      'Evening stretch',
    );
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Evening stretch'), findsOneWidget);
  });

  testWidgets('a deleted habit leaves the list', (tester) async {
    await _pump(tester, [_stretch, _walk]);

    await tester.tap(find.byKey(const Key('allHabits.habit.4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('habit.delete')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('allHabits.habit.4')), findsNothing);
    expect(find.byKey(const Key('allHabits.habit.5')), findsOneWidget);
  });

  testWidgets('with no habits it says so and offers to add one', (
    tester,
  ) async {
    await _pump(tester, []);

    expect(find.text('No habits yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('allHabits.empty.add')));
    await tester.pumpAndSettle();

    expect(_inSheet(find.text('New habit')), findsOneWidget);
  });

  testWidgets('a failed load offers Retry, which loads the list', (
    tester,
  ) async {
    final repo = _FakeRepo([_stretch])..failAllTimes = 1;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [routineRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: AllHabitsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Something broke.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('allHabits.retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('allHabits.habit.4')), findsOneWidget);
  });

  testWidgets('a habit added here says nothing about its repeat days', (
    tester,
  ) async {
    await _pump(tester, []);

    await tester.tap(find.byKey(const Key('allHabits.add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('habit.title')), 'Swim');
    // Tuesday and Thursday only, on a Monday: Daily Routine would announce.
    for (final weekday in [1, 3, 5, 6, 7]) {
      await tester.tap(find.byKey(Key('weekday.$weekday')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(
      find.text('Tue, Thu'),
      findsOneWidget,
      reason: 'the row says it instead',
    );
    expect(find.textContaining('repeats'), findsNothing);
  });
}
