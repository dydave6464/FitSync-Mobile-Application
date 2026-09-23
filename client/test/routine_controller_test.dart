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

ProviderContainer _container(_FakeRepo repo) {
  final c = ProviderContainer(
    overrides: [routineRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
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
}
