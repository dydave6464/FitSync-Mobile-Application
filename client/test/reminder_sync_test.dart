import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart'
    show activePlanProvider;
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show ProfileNotifier, profileProvider;
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart'
    show recoveryOverviewProvider;
import 'package:fitsync/features/reminders/data/reminder_scheduler.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart';
import 'package:fitsync/features/reminders/presentation/providers.dart'
    show ReminderSettingsController, reminderSettingsProvider;
import 'package:fitsync/features/reminders/presentation/reminder_sync.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart'
    show routineRepositoryProvider;

/// Records every call the widget under test makes, in order, so a test can
/// tell a stale run from the final one and check that cancelAll always
/// precedes the scheduleAll it belongs to.
class _FakeScheduler implements ReminderScheduler {
  final List<String> log = [];
  final List<List<PlannedReminder>> scheduleAllCalls = [];
  int cancelAllCount = 0;
  final tapsController = StreamController<String>.broadcast();

  @override
  Future<bool> permissionGranted() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> cancelAll() async {
    cancelAllCount += 1;
    log.add('cancelAll');
  }

  @override
  Future<void> scheduleAll(List<PlannedReminder> reminders) async {
    scheduleAllCalls.add(reminders);
    log.add('scheduleAll');
  }

  @override
  Stream<String> get taps => tapsController.stream;
}

/// A fixed answer instead of a repository round trip, mirroring
/// `_StubProfileNotifier` in home_screen_test.dart.
class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(this.profile);
  final Profile profile;

  @override
  Future<Profile> build() async => profile;
}

/// Returns a fixed settings value, and exposes a setter so a test can change
/// it mid-flight and watch ReminderSync react.
class _StubReminderSettings extends ReminderSettingsController {
  _StubReminderSettings(this._initial);
  final ReminderSettings _initial;

  @override
  Future<ReminderSettings> build() async => _initial;

  void set(ReminderSettings value) => state = AsyncData(value);
}

/// `all()` returns the given habits (or throws, if [allError] is set);
/// `today()` returns the given day. Every other member is unused by
/// ReminderSync and throws if called.
class _FakeRoutineRepository implements RoutineRepository {
  _FakeRoutineRepository({
    required this.habits,
    required this.day,
    this.allError,
  });

  final List<Habit> habits;
  final RoutineDay day;
  final Object? allError;

  @override
  Future<List<Habit>> all() async {
    if (allError != null) throw allError!;
    return habits;
  }

  @override
  Future<RoutineDay> today() async => day;

  @override
  Future<Habit> add(HabitDraft draft) => throw UnimplementedError();

  @override
  Future<Habit> edit(int habitId, HabitDraft draft) =>
      throw UnimplementedError();

  @override
  Future<void> remove(int habitId) => throw UnimplementedError();

  @override
  Future<void> check(int habitId, {String? date}) => throw UnimplementedError();

  @override
  Future<void> uncheck(int habitId, {String? date}) =>
      throw UnimplementedError();
}

const _stretchHabit = Habit(
  habitId: 1,
  title: 'Stretch',
  time: '06:30',
  durationMin: 8,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  done: false,
);

const _stretchHabitDoneToday = Habit(
  habitId: 1,
  title: 'Stretch',
  time: '06:30',
  durationMin: 8,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  done: true,
);

const _dayNotDone = RoutineDay(
  date: '2026-09-25',
  habits: [_stretchHabit],
  workout: null,
);

const _dayHabitDone = RoutineDay(
  date: '2026-09-25',
  habits: [_stretchHabitDoneToday],
  workout: null,
);

const _noCheckinRecovery = RecoveryOverview(
  todayCheckin: null,
  latestEstimate: null,
  load: [],
);

Profile _profile({bool notificationsEnabled = true}) => Profile(
  userId: 1,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: notificationsEnabled,
  equipment: const [],
  injuries: const [],
);

/// 22:00 UTC on the 24th is 06:00 Manila on the 25th -- well before every
/// fixture's reminder time, so today's occurrence is always still ahead of
/// "now" unless a test marks it done.
DateTime _now() => DateTime.utc(2026, 9, 24, 22);

class _Harness {
  _Harness(this.container, this.scheduler);
  final ProviderContainer container;
  final _FakeScheduler scheduler;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  ReminderSettings settings = ReminderSettings.defaults,
  List<Habit> habits = const [_stretchHabit],
  RoutineDay day = _dayNotDone,
  Object? habitsError,
  Profile? profile,
  RecoveryOverview recovery = _noCheckinRecovery,
  WorkoutPlan? plan,
  VoidCallback? onOpenRoutine,
  VoidCallback? onOpenRecovery,
}) async {
  final scheduler = _FakeScheduler();
  addTearDown(scheduler.tapsController.close);

  final container = ProviderContainer(
    overrides: [
      reminderSchedulerProvider.overrideWithValue(scheduler),
      reminderSettingsProvider.overrideWith(
        () => _StubReminderSettings(settings),
      ),
      profileProvider.overrideWith(
        () => _StubProfileNotifier(profile ?? _profile()),
      ),
      routineRepositoryProvider.overrideWithValue(
        _FakeRoutineRepository(habits: habits, day: day, allError: habitsError),
      ),
      recoveryOverviewProvider.overrideWith((ref) async => recovery),
      activePlanProvider.overrideWith((ref) async => plan),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ReminderSync(
          now: _now,
          onOpenRoutine: onOpenRoutine ?? () {},
          onOpenRecovery: onOpenRecovery ?? () {},
          child: const SizedBox(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Harness(container, scheduler);
}

void main() {
  testWidgets('on start it schedules the planned week', (tester) async {
    final harness = await _pump(tester);

    expect(
      harness.scheduler.scheduleAllCalls.last,
      hasLength(7),
      reason: 'one timed habit every day, none done today, for 7 days',
    );
    final lastCancel = harness.scheduler.log.lastIndexOf('cancelAll');
    final lastSchedule = harness.scheduler.log.lastIndexOf('scheduleAll');
    expect(
      lastCancel,
      lessThan(lastSchedule),
      reason: 'cancelAll must run before the scheduleAll it belongs to',
    );
  });

  testWidgets('the master switch off schedules nothing', (tester) async {
    final harness = await _pump(
      tester,
      profile: _profile(notificationsEnabled: false),
    );

    expect(harness.scheduler.scheduleAllCalls.last, isEmpty);
  });

  testWidgets('a change to settings reschedules', (tester) async {
    final harness = await _pump(tester);
    expect(harness.scheduler.scheduleAllCalls.last, hasLength(7));

    final callsBefore = harness.scheduler.scheduleAllCalls.length;
    (harness.container.read(
      reminderSettingsProvider.notifier,
    ) as _StubReminderSettings).set(
      const ReminderSettings(
        habitsEnabled: true,
        habitLeadMin: 15,
        workoutEnabled: false,
        workoutTime: '07:00',
        checkinEnabled: true,
        checkinTime: '07:00',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      harness.scheduler.scheduleAllCalls.length,
      greaterThan(callsBefore),
      reason: 'the settings change must trigger a fresh reschedule',
    );
    expect(
      harness.scheduler.scheduleAllCalls.last.any(
        (r) => r.payload == 'recovery',
      ),
      isTrue,
      reason: 'check-in reminders must now be in the plan',
    );
  });

  testWidgets("a habit ticked today drops today's reminder", (tester) async {
    final harness = await _pump(tester, day: _dayHabitDone);

    expect(harness.scheduler.scheduleAllCalls.last, hasLength(6));
  });

  testWidgets('when habits cannot be read, the existing schedule is kept', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      habitsError: Exception('routine unreachable'),
    );

    expect(harness.scheduler.cancelAllCount, 0);
    expect(harness.scheduler.scheduleAllCalls, isEmpty);
  });

  testWidgets('a tapped reminder opens routine or recovery', (tester) async {
    final opened = <String>[];
    final harness = await _pump(
      tester,
      onOpenRoutine: () => opened.add('routine'),
      onOpenRecovery: () => opened.add('recovery'),
    );

    harness.scheduler.tapsController.add('routine');
    await tester.pump();
    harness.scheduler.tapsController.add('recovery');
    await tester.pump();

    expect(opened, ['routine', 'recovery']);
  });
}
