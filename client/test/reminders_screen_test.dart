import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';
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

Future<_FakeScheduler> _pump(
  WidgetTester tester, {
  ReminderSettings settings = ReminderSettings.defaults,
  List<Map<String, dynamic>>? settingsPatches,
  List<Map<String, dynamic>>? profilePatches,
  bool granted = true,
  bool requestAnswer = true,
  Future<TimeOfDay?> Function(BuildContext, TimeOfDay)? pickTime,
}) async {
  final scheduler = _FakeScheduler(
    granted: granted,
    requestAnswer: requestAnswer,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reminderSettingsProvider.overrideWith(
          () => _RecordingReminderSettings(settings, patches: settingsPatches),
        ),
        profileProvider.overrideWith(
          () => FakeProfileNotifier(profilePatches ?? <Map<String, dynamic>>[]),
        ),
        reminderSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: MaterialApp(home: RemindersScreen(pickTime: pickTime)),
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
      tester.widget<FsSegmented>(find.byType(FsSegmented)).selected,
      '15',
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

    await tester.tap(find.byKey(const Key('segment.5')));
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
}
