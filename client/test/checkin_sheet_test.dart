import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/recovery/data/recovery_repository.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart';
import 'package:fitsync/features/recovery/presentation/widgets/checkin_sheet.dart';

class _FakeRepo implements RecoveryRepository {
  Map<String, String>? sent;
  Object? error;

  @override
  Future<InjuryRiskEstimate> checkIn(Map<String, String> answers) async {
    if (error != null) throw error!;
    sent = answers;
    return const InjuryRiskEstimate(
      riskLevel: 'moderate',
      trainingLoadScore: 40,
      checkinDate: '2026-09-20',
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// Lets a test hold `checkIn` open on a [Completer] it controls, so the
/// sheet can be dismissed while the request is still in flight, and counts
/// `overview()` calls so a test can tell whether the overview provider was
/// actually re-fetched after an invalidate, rather than just not-crashed.
class _SlowFakeRepo implements RecoveryRepository {
  _SlowFakeRepo(this._checkinCompleter);

  final Completer<InjuryRiskEstimate> _checkinCompleter;
  int overviewCalls = 0;

  @override
  Future<InjuryRiskEstimate> checkIn(Map<String, String> answers) =>
      _checkinCompleter.future;

  @override
  Future<RecoveryOverview> overview() async {
    overviewCalls++;
    return const RecoveryOverview(
      todayCheckin: null,
      latestEstimate: null,
      load: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

Future<_FakeRepo> _open(WidgetTester tester, {Object? error}) async {
  final repo = _FakeRepo()..error = error;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [recoveryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCheckinSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('it asks all four questions', (tester) async {
    await _open(tester);

    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Soreness'), findsOneWidget);
    expect(find.text('Energy'), findsOneWidget);
    expect(find.text('Stress'), findsOneWidget);
  });

  testWidgets('it posts the values the server stores', (tester) async {
    final repo = await _open(tester);

    await tester.tap(find.byKey(const Key('checkin.sleepQuality.poor')));
    await tester.tap(find.byKey(const Key('checkin.muscleSoreness.severe')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();

    // Column spellings, untouched.
    expect(repo.sent!['sleepQuality'], 'poor');
    expect(repo.sent!['muscleSoreness'], 'severe');
  });

  testWidgets('a failed save says so and does not claim it saved', (
    tester,
  ) async {
    await _open(tester, error: Exception('offline'));

    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(find.byKey(const Key('checkin.save')), findsOneWidget);
  });

  testWidgets(
    'dismissing the sheet mid-save still refreshes the overview once the '
    'save lands',
    (tester) async {
      final completer = Completer<InjuryRiskEstimate>();
      final repo = _SlowFakeRepo(completer);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [recoveryRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: fsLightTheme(),
            home: Consumer(
              builder: (context, ref, _) {
                // Mirrors the real Recovery screen sitting behind the sheet:
                // it already watches the overview, so there is a live
                // listener for an invalidate to actually refresh.
                ref.watch(recoveryOverviewProvider);
                return Scaffold(
                  body: TextButton(
                    onPressed: () => showCheckinSheet(context),
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.overviewCalls, 1);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checkin.save')));
      // Reach the in-flight await inside checkIn without resolving it.
      await tester.pump();

      // The swipe-to-dismiss the finding describes, done the way widget
      // tests dismiss a modal sheet: isDismissible defaults to true and
      // nothing here turns it off, so a tap on the scrim pops the route
      // exactly as a drag would.
      await tester.tapAt(const Offset(10, 10));
      // Let the exit transition finish so the sheet's State is actually
      // disposed -- not just scheduled to be -- before the save resolves.
      await tester.pumpAndSettle();

      // The save "lands" only now, after the sheet is gone.
      completer.complete(
        const InjuryRiskEstimate(
          riskLevel: 'moderate',
          trainingLoadScore: 40,
          checkinDate: '2026-09-20',
        ),
      );
      await tester.pumpAndSettle();

      // Against the unguarded `ref.invalidate` this call throws inside the
      // disposed sheet's own catch block, `mounted` is false, and the
      // method returns before the overview is ever re-fetched -- this count
      // would stay at 1.
      expect(repo.overviewCalls, 2);
    },
  );
}
