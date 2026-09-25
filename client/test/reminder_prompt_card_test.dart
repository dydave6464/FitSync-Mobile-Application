import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/token_store.dart' show InMemorySecureStore;
import 'package:fitsync/features/home/presentation/widgets/reminder_prompt_card.dart';
import 'package:fitsync/features/reminders/data/reminder_prompt_store.dart';
import 'package:fitsync/features/reminders/data/reminder_scheduler.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart';

/// Mirrors `_FakeScheduler` in reminders_screen_test.dart -- `granted`
/// answers `permissionGranted()`, and `pendingRequest`, when set, makes
/// `requestPermission` wait on a completer instead of answering immediately
/// so a test can hold the simulated system prompt open while the card is
/// disposed. The card hides on Turn on regardless of the answer, so no test
/// here needs `requestPermission` to resolve to anything but `true`.
class _FakeScheduler implements ReminderScheduler {
  _FakeScheduler({this.granted = false, this.pendingRequest});

  bool granted;
  int requestPermissionCalls = 0;
  final Completer<bool>? pendingRequest;

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls += 1;
    if (pendingRequest != null) return pendingRequest!.future;
    return true;
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> scheduleAll(List<PlannedReminder> reminders) async {}

  @override
  Stream<String> get taps => const Stream.empty();
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeScheduler scheduler,
  ReminderPromptStore? store,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reminderSchedulerProvider.overrideWithValue(scheduler),
        reminderPromptStoreProvider.overrideWithValue(
          store ?? ReminderPromptStore(backing: InMemorySecureStore()),
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
}
