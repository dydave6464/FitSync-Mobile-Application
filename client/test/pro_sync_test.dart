import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/pro/domain/pro_status.dart';
import 'package:fitsync/features/pro/presentation/pro_sync.dart';
import 'package:fitsync/features/pro/presentation/providers.dart';

import 'helpers/fake_pro_repository.dart';
import 'helpers/pro_locks_probe.dart';

/// Mounts [ProSync] the way the shell does, over a probe of what Pro gates.
Future<(FakeProRepository, ProLocksProbe, ProviderContainer)> _pump(
  WidgetTester tester, {
  required ProStatus status,
  required bool premium,
  Object? statusError,
}) async {
  final repo = FakeProRepository(status)..statusError = statusError;
  final probe = ProLocksProbe(premium: premium);
  final container = ProviderContainer(
    overrides: [
      proRepositoryProvider.overrideWithValue(repo),
      ...probe.overrides,
    ],
  );
  addTearDown(container.dispose);
  probe.watch(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProSync(child: SizedBox())),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, probe, container);
}

void main() {
  testWidgets(
    'a payment the server finished on its own unlocks Pro: the profile and '
    'the analytics are fetched again',
    (tester) async {
      // The app was killed on PayMongo's page; at the next launch the profile
      // still says free, and reading the status lets the server finish it.
      final (_, probe, _) = await _pump(
        tester,
        status: paidStatus(),
        premium: false,
      );
      expect(probe.profileLoads, 2);
      expect(probe.analyticsLoads, 2);
    },
  );

  testWidgets('a status that agrees with the profile fetches nothing again', (
    tester,
  ) async {
    final (_, probe, _) = await _pump(
      tester,
      status: freeStatus,
      premium: false,
    );
    expect(probe.profileLoads, 1);
    expect(probe.analyticsLoads, 1);
  });

  testWidgets('a Pro period that ended locks again', (tester) async {
    final (_, probe, _) = await _pump(
      tester,
      status: freeStatus,
      premium: true,
    );
    expect(probe.profileLoads, 2);
    expect(probe.analyticsLoads, 2);
  });

  testWidgets(
    'a profile that still disagrees after the refetch is not asked again',
    (tester) async {
      // One refetch per status read: a server whose two answers disagree
      // must not set off a loop.
      final (_, probe, container) = await _pump(
        tester,
        status: grantedStatus,
        premium: false,
      );
      expect(probe.profileLoads, 2);
      await tester.pump(const Duration(seconds: 5));
      expect(probe.profileLoads, 2);
      expect(probe.analyticsLoads, 2);

      // The next status read compares again.
      container.invalidate(proStatusProvider);
      await tester.pumpAndSettle();
      expect(probe.profileLoads, 3);
    },
  );

  testWidgets('the status is read once at launch, without a screen asking', (
    tester,
  ) async {
    final (repo, _, _) = await _pump(
      tester,
      status: freeStatus,
      premium: false,
    );
    expect(repo.statusCalls, 1);
  });

  testWidgets(
    'a launch read that failed is asked again when the app comes back',
    (tester) async {
      // Until a read succeeds the Settings card shows the free line, so a Pro
      // user who opened the app on a weak signal saw it all session.
      final (repo, probe, container) = await _pump(
        tester,
        status: paidStatus(),
        premium: false,
        statusError: Exception('offline'),
      );
      expect(repo.statusCalls, 1);
      expect(container.read(proStatusProvider).hasError, isTrue);

      repo.statusError = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repo.statusCalls, 2);
      expect(container.read(proStatusProvider).value?.pro, isTrue);
      expect(probe.profileLoads, 2, reason: 'and the Pro locks follow it');
    },
  );

  testWidgets('a status that loaded is not read again on every resume', (
    tester,
  ) async {
    final (repo, _, _) = await _pump(
      tester,
      status: freeStatus,
      premium: false,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.statusCalls, 1);
  });
}
