import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/app_settings.dart';
import 'package:fitsync/core/token_store.dart' show InMemorySecureStore;
import 'package:fitsync/features/home/presentation/widgets/reminder_prompt_card.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/reminders/data/reminder_prompt_store.dart';
import 'package:fitsync/features/reminders/data/reminder_scheduler.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart';

/// Mirrors `_FakeScheduler` in reminders_screen_test.dart -- `granted`
/// answers `permissionGranted()`, and `pendingRequest`, when set, makes
/// `requestPermission` wait on a completer instead of answering immediately
/// so a test can hold the simulated system prompt open while the card is
/// disposed. `requestAnswer` is what the system prompt answers otherwise.
class _FakeScheduler implements ReminderScheduler {
  _FakeScheduler({
    this.granted = false,
    this.pendingRequest,
    this.requestAnswer = true,
  });

  bool granted;
  final bool requestAnswer;
  int requestPermissionCalls = 0;
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

/// `answered()` fails every time -- a secure-storage read that genuinely
/// cannot land. Writes are left to the real in-memory backing, unused by the
/// test that needs this but harmless either way.
class _ThrowingAnsweredStore extends ReminderPromptStore {
  _ThrowingAnsweredStore() : super(backing: InMemorySecureStore());

  @override
  Future<bool> answered() =>
      Future<bool>.error(Exception('storage unavailable'));
}

/// The signed-in profile, whose notificationsEnabled is the reminders'
/// master switch.
class _StubProfile extends ProfileNotifier {
  _StubProfile({required this.masterOn});

  final bool masterOn;

  @override
  Future<Profile> build() async => Profile(
    userId: 1,
    email: 'juan@example.com',
    fullName: 'Juan Dela Cruz',
    onboardingCompleted: true,
    isPremium: false,
    notificationsEnabled: masterOn,
    equipment: const [],
    injuries: const [],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeScheduler scheduler,
  ReminderPromptStore? store,
  List<String>? settingsOpened,
  bool masterOn = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(() => _StubProfile(masterOn: masterOn)),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        reminderPromptStoreProvider.overrideWithValue(
          store ?? ReminderPromptStore(backing: InMemorySecureStore()),
        ),
        appSettingsOpenerProvider.overrideWithValue(
          () async => settingsOpened?.add('opened'),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ReminderPromptCard())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shown when permission is not granted and the prompt is unanswered',
    (tester) async {
      await _pump(tester, scheduler: _FakeScheduler(granted: false));

      expect(find.text('Get reminders for your habits'), findsOneWidget);
      expect(find.text('Turn on'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    },
  );

  testWidgets('its title is a heading, so moving by heading finds it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, scheduler: _FakeScheduler(granted: false));
    expect(
      tester
          .getSemantics(find.text('Get reminders for your habits'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('hidden when permission is already granted', (tester) async {
    await _pump(tester, scheduler: _FakeScheduler(granted: true));

    expect(find.text('Get reminders for your habits'), findsNothing);
  });

  testWidgets('hidden when the prompt has already been answered', (
    tester,
  ) async {
    final store = ReminderPromptStore(backing: InMemorySecureStore());
    await store.markAnswered();

    await _pump(
      tester,
      scheduler: _FakeScheduler(granted: false),
      store: store,
    );

    expect(find.text('Get reminders for your habits'), findsNothing);
  });

  testWidgets('hides when the answered check fails, instead of throwing', (
    tester,
  ) async {
    await _pump(
      tester,
      scheduler: _FakeScheduler(granted: false),
      store: _ThrowingAnsweredStore(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Get reminders for your habits'), findsNothing);
  });

  testWidgets('Turn on requests permission and hides the card for good', (
    tester,
  ) async {
    final scheduler = _FakeScheduler(granted: false);
    final store = ReminderPromptStore(backing: InMemorySecureStore());
    await _pump(tester, scheduler: scheduler, store: store);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCalls, 1);
    expect(find.text('Get reminders for your habits'), findsNothing);
    expect(
      await store.answered(),
      isTrue,
      reason: 'so a rebuild of Home never shows it again',
    );
  });

  testWidgets('Not now hides the card for good without requesting', (
    tester,
  ) async {
    final scheduler = _FakeScheduler(granted: false);
    final store = ReminderPromptStore(backing: InMemorySecureStore());
    await _pump(tester, scheduler: scheduler, store: store);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCalls, 0);
    expect(find.text('Get reminders for your habits'), findsNothing);
    expect(await store.answered(), isTrue);
  });

  testWidgets('disposing while the system prompt is up throws nothing', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final scheduler = _FakeScheduler(granted: false, pendingRequest: gate);
    await _pump(tester, scheduler: scheduler);

    await tester.tap(find.text('Turn on'));
    await tester.pump();

    // Replaces the card with something else entirely -- the same way the
    // Reminders screen's own mid-request test pops the route -- so the
    // State is disposed while requestPermission() is still awaiting.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump();

    gate.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Turn on, allowed, says reminders are on and where to change '
      'them', (tester) async {
    await _pump(tester, scheduler: _FakeScheduler(granted: false));

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Reminders on. Change them in Profile › Notifications & reminders.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Turn on, allowed, with reminders switched off in Profile, '
      'does not claim they are on', (tester) async {
    // The phone now allows notifications, but the app's own master switch
    // still sends none: "Reminders on" would be untrue.
    await _pump(
      tester,
      scheduler: _FakeScheduler(granted: false),
      masterOn: false,
    );

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Reminders on'), findsNothing);
    expect(
      find.text(
        'Notifications allowed. Turn reminders on in Profile › '
        'Notifications & reminders.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Turn on, refused, says notifications are blocked and offers '
      'the phone\'s settings', (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      scheduler: _FakeScheduler(granted: false, requestAnswer: false),
      settingsOpened: opened,
    );

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Notifications are blocked for FitSync. Allow them in your phone's "
        'settings to get reminders.',
      ),
      findsOneWidget,
    );
    expect(find.text('Get reminders for your habits'), findsNothing);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Open settings'));
    await tester.pumpAndSettle();
    expect(opened, ['opened']);
  });
}
