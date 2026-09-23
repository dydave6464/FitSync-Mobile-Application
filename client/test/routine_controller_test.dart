import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';

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
  int todayCalls = 0;
  final added = <HabitDraft>[];

  @override
  Future<RoutineDay> today() async {
    todayCalls++;
    return day;
  }

  Future<void> _maybeFail() async {
    if (failNext) {
      failNext = false;
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
  }

  @override
  Future<void> check(int habitId) => _maybeFail();
  @override
  Future<void> uncheck(int habitId) => _maybeFail();

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
  Future<void> check(int habitId) => _settle(habitId);
  @override
  Future<void> uncheck(int habitId) => _settle(habitId);
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
}
