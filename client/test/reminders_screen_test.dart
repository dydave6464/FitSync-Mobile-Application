import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/providers.dart'
    show appSettingsOpenerProvider;
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart'
    show activePlanProvider;
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/reminders/data/reminder_scheduler.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart';
import 'package:fitsync/features/reminders/presentation/providers.dart';
import 'package:fitsync/features/reminders/presentation/reminders_screen.dart';

import 'settings_screen_test.dart' show FakeProfileNotifier;

/// Records every `patch` this screen sends, mirroring `FakeProfileNotifier`
/// in settings_screen_test.dart -- this screen writes through two different
/// notifiers, so each gets its own recording fake.
class _RecordingReminderSettings extends ReminderSettingsController {
  _RecordingReminderSettings(this._initial, {this.patches});

  final ReminderSettings _initial;
  final List<Map<String, dynamic>>? patches;

  @override
  Future<ReminderSettings> build() async => _initial;

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    patches?.add(fields);
  }
}

/// `granted` answers `permissionGranted()`; `requestAnswer` is what
/// `requestPermission()` resolves to. The two are independent -- granting a
/// request in the real OS does not retroactively change what this fake
/// reports until a test says so -- so `requestPermissionCalls` is the only
/// signal a test needs that the screen asked at all.
class _FakeScheduler implements ReminderScheduler {
  _FakeScheduler({
    this.granted = true,
    this.requestAnswer = true,
    this.pendingRequest,
  });

  bool granted;
  bool requestAnswer;
  int requestPermissionCalls = 0;

  /// When set, `requestPermission()` waits on this instead of answering
  /// immediately -- so a test can hold the simulated system prompt open and
  /// pop the screen while it is still up.
  final Completer<bool>? pendingRequest;

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls += 1;
    if (pendingRequest != null) return pendingRequest!.future;
    return requestAnswer;
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> scheduleAll(List<PlannedReminder> reminders) async {}

  @override
  Stream<String> get taps => const Stream.empty();
}

/// Fails its first load, then answers [ReminderSettings.defaults] -- the
/// shape of a load that broke once and works on Try again.
class _FlakyReminderSettings extends ReminderSettingsController {
  _FlakyReminderSettings(this.loads);

  final List<int> loads;

  @override
  Future<ReminderSettings> build() async {
    loads.add(loads.length);
    if (loads.length == 1) {
      throw const ApiException('SERVER_ERROR', 'Reminder settings broke.');
    }
    return ReminderSettings.defaults;
  }
}

/// The profile [FakeProfileNotifier] seeds, but failing its first load.
class _FlakyProfile extends FakeProfileNotifier {
  _FlakyProfile(this.loads) : super(<Map<String, dynamic>>[]);

  final List<int> loads;

  @override
  Future<Profile> build() async {
    loads.add(loads.length);
    if (loads.length == 1) {
      throw const ApiException('SERVER_ERROR', 'Profile broke.');
    }
    return super.build();
  }
}

/// Holds every patch on [gate] until the test releases it, then saves it
/// the way the real controller does -- or fails, when the gate errors.
class _SlowReminderSettings extends ReminderSettingsController {
  _SlowReminderSettings(this.patches, this.gate);

  final List<Map<String, dynamic>> patches;
  final Completer<void> gate;

  @override
  Future<ReminderSettings> build() async => ReminderSettings.defaults;

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    patches.add(fields);
    await gate.future;
    final json = {
      'habitsEnabled': state.value!.habitsEnabled,
      'habitLeadMin': state.value!.habitLeadMin,
      'workoutEnabled': state.value!.workoutEnabled,
      'workoutTime': state.value!.workoutTime,
      'checkinEnabled': state.value!.checkinEnabled,
      'checkinTime': state.value!.checkinTime,
      ...fields,
    };
    state = AsyncData(ReminderSettings.fromJson(json));
  }
}

/// The seeded profile with the master switch off. [gate], when given, holds
/// every patch until the test completes it.
class _MasterOffProfile extends FakeProfileNotifier {
  _MasterOffProfile({Completer<void>? gate})
    : super(<Map<String, dynamic>>[], patchGate: gate);

  @override
  Future<Profile> build() async {
    final p = await super.build();
    return Profile(
      userId: p.userId,
      email: p.email,
      fullName: p.fullName,
      onboardingCompleted: p.onboardingCompleted,
      isPremium: p.isPremium,
      notificationsEnabled: false,
      equipment: p.equipment,
      injuries: p.injuries,
    );
  }
}

const _plan = WorkoutPlan(
  planId: 1,
  name: 'Full Body',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [],
);

Future<_FakeScheduler> _pump(
  WidgetTester tester, {
  ReminderSettings settings = ReminderSettings.defaults,
  List<Map<String, dynamic>>? settingsPatches,
  List<Map<String, dynamic>>? profilePatches,
  bool granted = true,
  bool requestAnswer = true,
  Future<TimeOfDay?> Function(BuildContext, TimeOfDay)? pickTime,
  ReminderSettingsController Function()? settingsController,
  ProfileNotifier Function()? profileNotifier,
  WorkoutPlan? plan = _plan,
  List<String>? settingsOpened,
  double textScale = 1.0,
}) async {
  final scheduler = _FakeScheduler(
    granted: granted,
    requestAnswer: requestAnswer,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reminderSettingsProvider.overrideWith(
          settingsController ??
              () => _RecordingReminderSettings(
                settings,
                patches: settingsPatches,
              ),
        ),
        profileProvider.overrideWith(
          profileNotifier ??
              () => FakeProfileNotifier(
                profilePatches ?? <Map<String, dynamic>>[],
              ),
        ),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        activePlanProvider.overrideWith((ref) async => plan),
        appSettingsOpenerProvider.overrideWithValue(
          () async => settingsOpened?.add('opened'),
        ),
      ],
      child: MaterialApp(
        home: RemindersScreen(pickTime: pickTime),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return scheduler;
}

/// Scrolls a key into view before tapping it. Several rows here sit low
/// enough in the `ListView` that a plain `tester.tap` derives an offset
/// outside the test viewport and silently misses -- the same trap
/// `_openRow` in settings_screen_test.dart exists to avoid.
Future<void> _scrollAndTap(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 200);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the saved settings', (tester) async {
    await _pump(tester);

    expect(find.text('Reminders'), findsOneWidget);
    expect(
      tester.widget<Switch>(find.byKey(const Key('reminders.master'))).value,
      isTrue,
    );
    expect(
      tester.widget<Switch>(find.byKey(const Key('reminders.habits'))).value,
      isTrue,
    );
    expect(
      tester
          .widget<FsChip>(find.byKey(const Key('reminders.lead.15')))
          .selected,
      isTrue,
      reason: 'the default habitLeadMin is 15',
    );
    expect(
      tester.widget<Switch>(find.byKey(const Key('reminders.workout'))).value,
      isFalse,
    );
    expect(
      tester.widget<Switch>(find.byKey(const Key('reminders.checkin'))).value,
      isFalse,
    );
    expect(
      find.text('7:00 AM'),
      findsNWidgets(2),
      reason: 'workoutTime and checkinTime both default to 07:00',
    );
  });

  testWidgets('the master switch writes the profile', (tester) async {
    final profilePatches = <Map<String, dynamic>>[];
    await _pump(tester, profilePatches: profilePatches);

    await tester.tap(find.byKey(const Key('reminders.master')));
    await tester.pumpAndSettle();

    expect(profilePatches, [
      {'notificationsEnabled': false},
    ]);
  });

  testWidgets('choosing a lead time saves it', (tester) async {
    final settingsPatches = <Map<String, dynamic>>[];
    await _pump(tester, settingsPatches: settingsPatches);

    await tester.tap(find.byKey(const Key('reminders.lead.5')));
    await tester.pumpAndSettle();

    expect(settingsPatches, [
      {'habitLeadMin': 5},
    ]);
  });

  testWidgets(
    'turning a reminder on asks for permission first when it is not granted',
    (tester) async {
      final settingsPatches = <Map<String, dynamic>>[];
      final scheduler = await _pump(
        tester,
        granted: false,
        requestAnswer: true,
        settingsPatches: settingsPatches,
      );

      await _scrollAndTap(tester, const Key('reminders.checkin'));

      expect(scheduler.requestPermissionCalls, 1);
      expect(settingsPatches, [
        {'checkinEnabled': true},
      ]);
    },
  );

  testWidgets('a refused permission leaves the reminder off and says why', (
    tester,
  ) async {
    final settingsPatches = <Map<String, dynamic>>[];
    await _pump(
      tester,
      granted: false,
      requestAnswer: false,
      settingsPatches: settingsPatches,
    );

    await _scrollAndTap(tester, const Key('reminders.checkin'));

    expect(settingsPatches, isEmpty);
    // Back up to the top, where the banner is.
    await tester.scrollUntilVisible(
      find.byKey(const Key('reminders.blocked')),
      -200,
    );
    expect(find.byKey(const Key('reminders.blocked')), findsOneWidget);
  });

  testWidgets('picking a workout time saves HH:MM', (tester) async {
    final settingsPatches = <Map<String, dynamic>>[];
    await _pump(
      tester,
      settingsPatches: settingsPatches,
      pickTime: (context, initial) async =>
          const TimeOfDay(hour: 18, minute: 30),
    );

    await _scrollAndTap(tester, const Key('reminders.workoutTime'));

    expect(settingsPatches, [
      {'workoutTime': '18:30'},
    ]);
  });

  testWidgets('with permission blocked the banner shows', (tester) async {
    await _pump(tester, granted: false);

    expect(find.byKey(const Key('reminders.blocked')), findsOneWidget);
    expect(
      find.text(
        "Notifications are blocked for FitSync. Allow them in your "
        "phone's settings to get reminders.",
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the blocked banner clears when permission is granted while the screen '
    'is open',
    (tester) async {
      final scheduler = await _pump(tester, granted: false);
      expect(find.byKey(const Key('reminders.blocked')), findsOneWidget);

      scheduler.granted = true;

      // Mirrors `resume` in day_rollover_test.dart.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reminders.blocked')), findsNothing);
    },
  );

  testWidgets(
    'popping the screen while permission is being asked does not throw',
    (tester) async {
      final settingsPatches = <Map<String, dynamic>>[];
      final pendingRequest = Completer<bool>();
      final scheduler = _FakeScheduler(
        granted: false,
        pendingRequest: pendingRequest,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reminderSettingsProvider.overrideWith(
              () => _RecordingReminderSettings(
                ReminderSettings.defaults,
                patches: settingsPatches,
              ),
            ),
            profileProvider.overrideWith(
              () => FakeProfileNotifier(<Map<String, dynamic>>[]),
            ),
            reminderSchedulerProvider.overrideWithValue(scheduler),
          ],
          // A route below RemindersScreen, so the test can pop it -- unlike
          // every other test here, which puts it straight at `home` with
          // nothing to pop to.
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RemindersScreen(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('reminders.checkin')),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminders.checkin')));
      // A plain pump, not pumpAndSettle: `requestPermission()` is parked on
      // `pendingRequest`, so the widget is mid-await, exactly where a real
      // system prompt would leave it while still on screen.
      await tester.pump();

      Navigator.of(tester.element(find.byType(RemindersScreen))).pop();
      await tester.pumpAndSettle();

      // The prompt is "answered" only after the screen is already gone --
      // the resumed `_setEnabled` must see `mounted == false` and stop
      // rather than touch `ref` or `context` again.
      pendingRequest.complete(true);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(settingsPatches, isEmpty);
    },
  );

  testWidgets('a settings load error offers Try again, which reloads', (
    tester,
  ) async {
    final loads = <int>[];
    await _pump(
      tester,
      settingsController: () => _FlakyReminderSettings(loads),
    );

    expect(
      find.text('Reminder settings broke.'),
      findsOneWidget,
      reason: 'the plain message (userMessage) is shown',
    );
    expect(find.byType(FsRetry), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminders.retry')));
    await tester.pumpAndSettle();

    expect(loads, hasLength(2));
    expect(find.byType(FsRetry), findsNothing);
    expect(find.byKey(const Key('reminders.master')), findsOneWidget);
  });

  testWidgets('a profile load error offers Try again, which reloads', (
    tester,
  ) async {
    final loads = <int>[];
    await _pump(tester, profileNotifier: () => _FlakyProfile(loads));

    expect(find.text('Profile broke.'), findsOneWidget);
    expect(find.byType(FsRetry), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminders.retry')));
    await tester.pumpAndSettle();

    expect(loads, hasLength(2));
    expect(find.byKey(const Key('reminders.master')), findsOneWidget);
  });

  testWidgets('each switch is named by its row', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    for (final (key, label) in [
      ('reminders.master', 'Notifications & reminders'),
      ('reminders.habits', 'Remind me about habits'),
      ('reminders.workout', 'Remind me before my workout'),
      ('reminders.checkin', 'Remind me to check in'),
    ]) {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 200);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(Key(key))),
        matchesSemantics(
          label: label,
          hasToggledState: true,
          isToggled: key != 'reminders.workout' && key != 'reminders.checkin',
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
        reason: key,
      );
    }
    handle.dispose();
  });

  testWidgets('with the master switch off the sections say so and are '
      'disabled', (tester) async {
    final settingsPatches = <Map<String, dynamic>>[];
    await _pump(
      tester,
      profileNotifier: _MasterOffProfile.new,
      settingsPatches: settingsPatches,
    );

    expect(
      find.text(
        'Reminders are off. Turn this on to get any of the reminders below.',
      ),
      findsOneWidget,
    );
    for (final key in [
      'reminders.habits',
      'reminders.workout',
      'reminders.checkin',
    ]) {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 200);
      expect(
        tester.widget<Switch>(find.byKey(Key(key))).onChanged,
        isNull,
        reason: '$key is disabled while nothing can fire',
      );
    }
    expect(
      tester.widget<FsChip>(find.byKey(const Key('reminders.lead.5'))).onTap,
      isNull,
      reason: 'the lead time is disabled too',
    );
    // The master switch itself stays live: it is the way back.
    await tester.scrollUntilVisible(
      find.byKey(const Key('reminders.master')),
      -200,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('reminders.master')))
          .onChanged,
      isNotNull,
    );
    // A tap on a disabled time row: see the next test.
  });

  // A time picker that answers at once: without it, the default picker is a
  // dialog that never returns in a test, so "saves nothing" could not fail.
  testWidgets('with the master switch off a time row saves nothing', (
    tester,
  ) async {
    final settingsPatches = <Map<String, dynamic>>[];
    var picks = 0;
    await _pump(
      tester,
      profileNotifier: _MasterOffProfile.new,
      settingsPatches: settingsPatches,
      pickTime: (_, _) async {
        picks += 1;
        return const TimeOfDay(hour: 9, minute: 30);
      },
    );

    await _scrollAndTap(tester, const Key('reminders.workoutTime'));

    expect(picks, 0, reason: 'the picker never opens');
    expect(settingsPatches, isEmpty);
  });

  // The sections followed the saved master value, so for as long as turning
  // it on was on its way the switch read On over sections still dimmed and
  // disabled under "Reminders are off".
  testWidgets('the sections come alive as soon as the master switch is '
      'turned on', (tester) async {
    final gate = Completer<void>();
    await _pump(tester, profileNotifier: () => _MasterOffProfile(gate: gate));

    await tester.tap(find.byKey(const Key('reminders.master')));
    await tester.pump();

    expect(find.textContaining('Reminders are off.'), findsNothing);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('reminders.habits')))
          .onChanged,
      isNotNull,
    );
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('with the master switch on there is no "off" line', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Reminders are off.'), findsNothing);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('reminders.habits')))
          .onChanged,
      isNotNull,
    );
  });

  testWidgets('Habits says only timed habits are reminded', (tester) async {
    await _pump(tester);

    expect(
      find.text('Only habits with a set time get a reminder.'),
      findsOneWidget,
    );
  });

  testWidgets('without a plan the workout section says it needs one', (
    tester,
  ) async {
    await _pump(tester, plan: null);
    await tester.scrollUntilVisible(
      find.text('Workout reminders need a plan.'),
      200,
    );
    expect(find.text('Workout reminders need a plan.'), findsOneWidget);
  });

  testWidgets('with a plan the workout section has no plan note', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Workout reminders need a plan.'), findsNothing);
  });

  testWidgets('the blocked banner opens the phone\'s settings', (tester) async {
    final opened = <String>[];
    await _pump(tester, granted: false, settingsOpened: opened);

    final button = find.descendant(
      of: find.byKey(const Key('reminders.blocked')),
      matching: find.widgetWithText(FsButton, 'Open settings'),
    );
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(opened, ['opened']);
  });

  bool switchOn(WidgetTester tester, String key) =>
      tester.widget<Switch>(find.byKey(Key(key))).value;

  testWidgets('a switch moves at once and a second tap while saving sends '
      'nothing more', (tester) async {
    final patches = <Map<String, dynamic>>[];
    final gate = Completer<void>();
    await _pump(
      tester,
      settingsController: () => _SlowReminderSettings(patches, gate),
    );
    expect(switchOn(tester, 'reminders.habits'), isTrue);

    await tester.tap(find.byKey(const Key('reminders.habits')));
    await tester.pump();
    expect(
      switchOn(tester, 'reminders.habits'),
      isFalse,
      reason: 'the switch shows the new value while the server is asked',
    );

    await tester.tap(find.byKey(const Key('reminders.habits')));
    await tester.pump();
    expect(patches, [
      {'habitsEnabled': false},
    ], reason: 'no duplicate PATCH while one is in flight');
    expect(switchOn(tester, 'reminders.habits'), isFalse);

    gate.complete();
    await tester.pumpAndSettle();
    expect(switchOn(tester, 'reminders.habits'), isFalse);
  });

  testWidgets('the selected lead time does nothing when tapped', (
    tester,
  ) async {
    final settingsPatches = <Map<String, dynamic>>[];
    await _pump(tester, settingsPatches: settingsPatches);

    await tester.tap(find.byKey(const Key('reminders.lead.15')));
    await tester.pumpAndSettle();

    expect(settingsPatches, isEmpty, reason: '15 is already the lead time');
  });

  testWidgets('a lead time moves at once and more taps while saving send '
      'nothing more', (tester) async {
    final patches = <Map<String, dynamic>>[];
    final gate = Completer<void>();
    await _pump(
      tester,
      settingsController: () => _SlowReminderSettings(patches, gate),
    );
    bool selected(String value) => tester
        .widget<FsChip>(find.byKey(Key('reminders.lead.$value')))
        .selected;

    await tester.tap(find.byKey(const Key('reminders.lead.5')));
    await tester.pump();
    expect(selected('5'), isTrue, reason: 'shown while the server is asked');
    expect(selected('15'), isFalse);

    await tester.tap(find.byKey(const Key('reminders.lead.5')));
    await tester.tap(find.byKey(const Key('reminders.lead.30')));
    await tester.pump();
    expect(patches, [
      {'habitLeadMin': 5},
    ], reason: 'no further PATCH while one is in flight');
    expect(selected('5'), isTrue);

    gate.complete();
    await tester.pumpAndSettle();
    expect(selected('5'), isTrue);
  });

  testWidgets('a failed save puts the switch back and says why', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    final gate = Completer<void>();
    await _pump(
      tester,
      settingsController: () => _SlowReminderSettings(patches, gate),
    );

    await tester.tap(find.byKey(const Key('reminders.habits')));
    await tester.pump();
    expect(switchOn(tester, 'reminders.habits'), isFalse);

    gate.completeError(
      const ApiException('SERVER_ERROR', 'That could not be saved.'),
    );
    await tester.pumpAndSettle();

    expect(switchOn(tester, 'reminders.habits'), isTrue);
    expect(find.text('That could not be saved.'), findsOneWidget);
  });

  testWidgets('a refused permission puts the switch back', (tester) async {
    await _pump(tester, granted: false, requestAnswer: false);

    await _scrollAndTap(tester, const Key('reminders.checkin'));

    expect(switchOn(tester, 'reminders.checkin'), isFalse);
  });

  testWidgets('each time row is 48 dp tall and says which time it is', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    for (final (key, label) in [
      ('reminders.workoutTime', 'Workout reminder time, 7:00 AM'),
      ('reminders.checkinTime', 'Check-in reminder time, 7:00 AM'),
    ]) {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 200);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
        reason: key,
      );
      expect(
        tester.getSemantics(find.byKey(Key(key))),
        matchesSemantics(
          label: label,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
        reason: key,
      );
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('the lead time is a set of chips, one of them selected', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(find.byType(FsSegmented), findsNothing);
    for (final (value, label) in [
      ('0', 'At the time'),
      ('5', '5 min before'),
      ('15', '15 min before'),
      ('30', '30 min before'),
    ]) {
      final chip = find.byKey(Key('reminders.lead.$value'));
      expect(
        find.descendant(of: chip, matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        tester.widget<FsChip>(chip).selected,
        value == '15',
        reason: 'the default habitLeadMin is 15',
      );
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  for (final size in [const Size(360, 640), const Size(320, 568)]) {
    testWidgets('at 2x text on ${size.width.toInt()} dp every lead time '
        'reads whole', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester, textScale: 2.0);

      expect(tester.takeException(), isNull);
      for (final label in [
        'At the time',
        '5 min before',
        '15 min before',
        '30 min before',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 100);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
      // And nothing further down the screen overflows either.
      await tester.scrollUntilVisible(
        find.byKey(const Key('reminders.checkinTime')),
        200,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
