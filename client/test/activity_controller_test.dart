import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/activity/data/activity_repository.dart';
import 'package:fitsync/features/activity/data/step_permission.dart';
import 'package:fitsync/features/activity/data/step_source.dart';
import 'package:fitsync/features/activity/domain/activity.dart';
import 'package:fitsync/features/activity/domain/step_readings.dart';
import 'package:fitsync/features/activity/presentation/providers.dart';

// 2026-09-28 10:00 Manila
final _now = DateTime.utc(2026, 9, 28, 2);

ActivityDay _d(String date, int? steps) => ActivityDay(
  date: date, steps: steps, caloriesBurned: steps == null ? null : 100,
  distanceKm: steps == null ? null : 3.0, activeMinutes: steps == null ? null : 40,
);

ActivityWeek _week(Map<String, int> stored) => ActivityWeek(
  days: [
    for (var d = 22; d <= 28; d++) _d('2026-09-$d', stored['2026-09-$d']),
  ],
  usual: null,
  missing: const [],
);

class _FakeSource implements StepSource {
  _FakeSource({this.todaySteps = 0, this.earlier = const {}});
  int todaySteps;
  Map<String, int> earlier;

  @override
  Future<DaySteps> today(DateTime now) async => DaySteps(steps: todaySteps);
  @override
  Future<Map<String, int>> earlierDays(DateTime now) async => earlier;
  @override
  Stream<int> live(DateTime now) => const Stream.empty();
}

class _FakePermission implements StepPermission {
  _FakePermission({
    this.statusValue = StepAccess.notAsked,
    this.requestValue = StepAccess.granted,
  });
  StepAccess statusValue;
  StepAccess requestValue;
  int openSettingsCalls = 0;

  @override
  Future<StepAccess> status() async => statusValue;
  @override
  Future<StepAccess> request() async => requestValue;
  @override
  Future<void> openSettings() async => openSettingsCalls += 1;
}

class _FakeRepo implements ActivityRepository {
  final stored = <String, int>{};
  final saves = <String>[];
  Object? failWith;

  @override
  Future<ActivityDay> saveDay(String date, int steps) async {
    if (failWith != null) throw failWith!;
    saves.add('$date=$steps');
    stored[date] = steps > (stored[date] ?? -1) ? steps : stored[date]!;
    return _d(date, stored[date]);
  }

  @override
  Future<ActivityWeek> week() async {
    if (failWith != null) throw failWith!;
    return _week(stored);
  }
}

ProviderContainer _container(_FakeSource source, _FakeRepo repo) {
  final c = ProviderContainer(overrides: [
    stepSourceProvider.overrideWithValue(source),
    activityRepositoryProvider.overrideWithValue(repo),
    activityClockProvider.overrideWithValue(() => _now),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('loading saves today and returns the week', () async {
    final repo = _FakeRepo();
    final c = _container(_FakeSource(todaySteps: 6420), repo);

    final s = await c.read(activityProvider.future);

    expect(repo.saves, ['2026-09-28=6420']);
    expect(s.today.steps, 6420);
    expect(s.week!.today.steps, 6420);
    expect(s.offline, isFalse);
  });

  test('earlier days are saved only where the phone has more than the server, never 0', () async {
    final repo = _FakeRepo()..stored.addAll({'2026-09-27': 5000, '2026-09-26': 9000});
    final c = _container(
      _FakeSource(todaySteps: 100, earlier: {'2026-09-27': 5200, '2026-09-26': 9000, '2026-09-25': 0}),
      repo,
    );

    await c.read(activityProvider.future);

    expect(repo.saves, ['2026-09-28=100', '2026-09-27=5200']);
  });

  test('offline: today still counts, the week is the last one, flagged', () async {
    final repo = _FakeRepo();
    final source = _FakeSource(todaySteps: 1000);
    final c = _container(source, repo);
    await c.read(activityProvider.future);

    repo.failWith = const ApiException('NETWORK_ERROR', 'offline');
    source.todaySteps = 1500;
    await c.read(activityProvider.notifier).sync();

    final s = c.read(activityProvider).value!;
    expect(s.today.steps, 1500);
    expect(s.week!.today.steps, 1000);
    expect(s.offline, isTrue);
  });

  test('a server error on sync keeps the last good state', () async {
    final repo = _FakeRepo();
    final c = _container(_FakeSource(todaySteps: 1000), repo);
    await c.read(activityProvider.future);

    repo.failWith = const ApiException('SERVER_ERROR', 'broke');
    await c.read(activityProvider.notifier).sync();

    expect(c.read(activityProvider).value!.today.steps, 1000);
    expect(c.read(activityProvider).value!.offline, isFalse);
  });

  test('a server error on first load is an error', () async {
    final repo = _FakeRepo()..failWith = const ApiException('SERVER_ERROR', 'broke');
    final c = _container(_FakeSource(), repo);

    await expectLater(c.read(activityProvider.future), throwsA(isA<ApiException>()));
  });

  test('0 steps today are never saved', () async {
    final repo = _FakeRepo();
    final c = _container(_FakeSource(todaySteps: 0), repo);

    await c.read(activityProvider.future);

    expect(repo.saves, isEmpty);
  });

  test(
    'StepAccessController reads status, applies request, and delegates '
    'openSettings',
    () async {
      final permission = _FakePermission(
        statusValue: StepAccess.refused,
        requestValue: StepAccess.granted,
      );
      final c = ProviderContainer(
        overrides: [stepPermissionProvider.overrideWithValue(permission)],
      );
      addTearDown(c.dispose);

      expect(await c.read(stepAccessProvider.future), StepAccess.refused);

      final result = await c.read(stepAccessProvider.notifier).request();

      expect(result, StepAccess.granted);
      expect(c.read(stepAccessProvider).value, StepAccess.granted);

      await c.read(stepAccessProvider.notifier).openSettings();
      expect(permission.openSettingsCalls, 1);
    },
  );
}
