import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart';

const _habit = Habit(
  habitId: 1,
  title: 'Mobility',
  time: null,
  durationMin: null,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  done: false,
);

class _FakeRepo implements RoutineRepository {
  RoutineDay day = const RoutineDay(
    date: '2026-09-21',
    habits: [_habit],
    workout: null,
  );
  bool failNext = false;
  bool failNextToday = false;
  String failCode = 'NETWORK_ERROR';
  int todayCalls = 0;
  int allCalls = 0;
  final added = <HabitDraft>[];
  final checkDates = <String?>[];

  @override
  Future<RoutineDay> today() async {
    todayCalls++;
    if (failNextToday) {
      failNextToday = false;
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
    return day;
  }

  Future<void> _maybeFail() async {
    if (failNext) {
      failNext = false;
      throw ApiException(failCode, 'offline');
    }
  }

  @override
  Future<void> check(int habitId, {String? date}) {
    checkDates.add(date);
    return _maybeFail();
  }

  @override
  Future<void> uncheck(int habitId, {String? date}) {
    checkDates.add(date);
    return _maybeFail();
  }

  @override
  Future<List<Habit>> all() async {
    allCalls++;
    return const [_habit];
  }

  @override
  Future<Habit> add(HabitDraft draft) async {
    await _maybeFail();
    added.add(draft);
    return _habit;
  }

  @override
  Future<Habit> edit(int habitId, HabitDraft draft) async => _habit;
  @override
  Future<void> remove(int habitId) async {}
}

ProviderContainer _container(RoutineRepository repo) {
  final c = ProviderContainer(
    overrides: [routineRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

/// A repo whose `check`/`uncheck` wait on a per-habit [Completer], so a test
/// can decide exactly which of two in-flight ticks resolves first.
class _ControlledRepo implements RoutineRepository {
  _ControlledRepo(this.day);

  RoutineDay day;
  final _gates = <int, Completer<void>>{};
  final _shouldFail = <int>{};
  final checkCalls = <int>[];

  Completer<void> gateFor(int habitId) =>
      _gates.putIfAbsent(habitId, Completer<void>.new);

  void willFail(int habitId) => _shouldFail.add(habitId);

  Future<void> _settle(int habitId) async {
    checkCalls.add(habitId);
    await gateFor(habitId).future;
    if (_shouldFail.remove(habitId)) {
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
  }

  @override
  Future<RoutineDay> today() async => day;
  @override
  Future<void> check(int habitId, {String? date}) => _settle(habitId);
  @override
  Future<void> uncheck(int habitId, {String? date}) => _settle(habitId);
  @override
  Future<List<Habit>> all() async => throw UnimplementedError();
  @override
  Future<Habit> add(HabitDraft draft) async => throw UnimplementedError();
  @override
  Future<Habit> edit(int habitId, HabitDraft draft) async =>
      throw UnimplementedError();
  @override
  Future<void> remove(int habitId) async => throw UnimplementedError();
}

void main() {
  test('ticking shows at once and stays when the save lands', () async {
    final repo = _FakeRepo();
    final c = _container(repo);
    await c.read(routineTodayProvider.future);

    final pending = c.read(routineTodayProvider.notifier).setDone(1, true);
    expect(
      c.read(routineTodayProvider).value!.habits.single.done,
      isTrue,
      reason: 'optimistic: before the save answers',
    );
    await pending;
    expect(c.read(routineTodayProvider).value!.habits.single.done, isTrue);
  });

  test('a failed tick puts it back and rethrows', () async {
    final repo = _FakeRepo()..failNext = true;
    final c = _container(repo);
    await c.read(routineTodayProvider.future);

    await expectLater(
      c.read(routineTodayProvider.notifier).setDone(1, true),
      throwsA(isA<ApiException>()),
    );
    expect(c.read(routineTodayProvider).value!.habits.single.done, isFalse);
  });

  test('a tick sends the day the screen is showing', () async {
    final repo = _FakeRepo();
    final c = _container(repo);
    await c.read(routineTodayProvider.future);

    await c.read(routineTodayProvider.notifier).setDone(1, true);

    expect(repo.checkDates, ['2026-09-21']);
  });

  test('a DAY_CHANGED failure reloads the day, then rethrows', () async {
    final repo = _FakeRepo()
      ..failNext = true
      ..failCode = 'DAY_CHANGED';
    final c = _container(repo);
    await c.read(routineTodayProvider.future);
    final callsBefore = repo.todayCalls;

    await expectLater(
      c.read(routineTodayProvider.notifier).setDone(1, true),
      throwsA(isA<ApiException>()),
    );

    expect(
      repo.todayCalls,
      greaterThan(callsBefore),
      reason: 'the day was reloaded so the screen shows the new day',
    );
  });

  test('a HABIT_NOT_TODAY failure reloads the day, then rethrows', () async {
    final repo = _FakeRepo()
      ..failNext = true
      ..failCode = 'HABIT_NOT_TODAY';
    final c = _container(repo);
    await c.read(routineTodayProvider.future);
    final callsBefore = repo.todayCalls;

    await expectLater(
      c.read(routineTodayProvider.notifier).setDone(1, true),
      throwsA(isA<ApiException>()),
    );

    expect(repo.todayCalls, greaterThan(callsBefore));
  });

  test('adding saves the draft and reloads the day', () async {
    final repo = _FakeRepo();
    final c = _container(repo);
    await c.read(routineTodayProvider.future);
    final before = repo.todayCalls;

    await c
        .read(routineTodayProvider.notifier)
        .add(
          const HabitDraft(
            title: 'Walk',
            time: null,
            durationMin: null,
            weekdays: [1],
          ),
        );

    expect(repo.added.single.title, 'Walk');
    expect(repo.todayCalls, greaterThan(before));
  });

  test('a failed add rethrows so the sheet can say so', () async {
    final repo = _FakeRepo()..failNext = true;
    final c = _container(repo);
    await c.read(routineTodayProvider.future);
    await expectLater(
      c
          .read(routineTodayProvider.notifier)
          .add(
            const HabitDraft(
              title: 'Walk',
              time: null,
              durationMin: null,
              weekdays: [1],
            ),
          ),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'a save that lands counts as saved even if the reload after it fails',
    () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      await c.read(routineTodayProvider.future);
      repo.failNextToday = true;

      await c
          .read(routineTodayProvider.notifier)
          .add(
            const HabitDraft(
              title: 'Walk',
              time: null,
              durationMin: null,
              weekdays: [1],
            ),
          );

      expect(repo.added, hasLength(1));
    },
  );

  test('a failed tick rolls back only itself, not a concurrent tick that '
      'succeeded', () async {
    const habitA = Habit(
      habitId: 1,
      title: 'A',
      time: null,
      durationMin: null,
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      done: false,
    );
    const habitB = Habit(
      habitId: 2,
      title: 'B',
      time: null,
      durationMin: null,
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      done: false,
    );
    final repo = _ControlledRepo(
      const RoutineDay(
        date: '2026-09-21',
        habits: [habitA, habitB],
        workout: null,
      ),
    )..willFail(1);
    final c = _container(repo);
    await c.read(routineTodayProvider.future);
    final notifier = c.read(routineTodayProvider.notifier);

    final futureA = notifier.setDone(1, true);
    final futureB = notifier.setDone(2, true);

    // B's write resolves first...
    repo.gateFor(2).complete();
    await futureB;
    expect(
      c.read(routineTodayProvider).value!.habits[1].done,
      isTrue,
      reason: "B's tick landed",
    );

    // ...then A's fails.
    repo.gateFor(1).complete();
    await expectLater(futureA, throwsA(isA<ApiException>()));

    final day = c.read(routineTodayProvider).value!;
    expect(day.habits[0].done, isFalse, reason: "A's failed tick rolls back");
    expect(
      day.habits[1].done,
      isTrue,
      reason: "B's tick must survive A's rollback",
    );
  });

  test(
    'a second tap on a habit mid-save makes no second repository call',
    () async {
      final repo = _ControlledRepo(
        const RoutineDay(date: '2026-09-21', habits: [_habit], workout: null),
      );
      final c = _container(repo);
      await c.read(routineTodayProvider.future);
      final notifier = c.read(routineTodayProvider.notifier);

      final first = notifier.setDone(1, true);
      await notifier.setDone(1, false);

      expect(repo.checkCalls, [1], reason: 'the second tap made no call');

      repo.gateFor(1).complete();
      await first;
    },
  );

  test('adding, editing and deleting each refetch the full list', () async {
    final repo = _FakeRepo();
    final c = _container(repo);
    await c.read(routineTodayProvider.future);
    // Held open, as the All habits screen holds it; autoDispose otherwise.
    final sub = c.listen(allHabitsProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(allHabitsProvider.future);
    expect(repo.allCalls, 1);

    final notifier = c.read(routineTodayProvider.notifier);
    const draft = HabitDraft(
      title: 'Walk',
      time: null,
      durationMin: null,
      weekdays: [1],
    );

    await notifier.add(draft);
    await c.read(allHabitsProvider.future);
    expect(repo.allCalls, 2, reason: 'after add');

    await notifier.edit(1, draft);
    await c.read(allHabitsProvider.future);
    expect(repo.allCalls, 3, reason: 'after edit');

    await notifier.remove(1);
    await c.read(allHabitsProvider.future);
    expect(repo.allCalls, 4, reason: 'after remove');
  });

  test(
    'a tick that lands refreshes the streak; one that fails does not',
    () async {
      var streakBuilds = 0;
      final repo = _FakeRepo();
      final c = ProviderContainer(
        overrides: [
          routineRepositoryProvider.overrideWithValue(repo),
          streakProvider.overrideWith((ref) async {
            streakBuilds++;
            return const Streak(
              current: 0,
              best: 0,
              todayActive: false,
              week: [],
            );
          }),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(streakProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(streakProvider.future);
      await c.read(routineTodayProvider.future);
      expect(streakBuilds, 1);

      await c.read(routineTodayProvider.notifier).setDone(_habit.habitId, true);
      await c.read(streakProvider.future);
      expect(streakBuilds, 2, reason: 'a landed tick');

      repo.failNext = true;
      await expectLater(
        c.read(routineTodayProvider.notifier).setDone(_habit.habitId, false),
        throwsA(isA<ApiException>()),
      );
      await c.read(streakProvider.future);
      expect(streakBuilds, 2, reason: 'a failed tick changed nothing');
    },
  );
}
