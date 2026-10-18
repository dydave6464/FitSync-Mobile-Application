import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/recovery/data/recovery_repository.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart';
import 'package:fitsync/features/recovery/presentation/widgets/checkin_sheet.dart';

class _FakeRepo implements RecoveryRepository {
  Map<String, String>? sent;
  Object? error;

  @override
  Future<void> checkIn(Map<String, String> answers) async {
    if (error != null) throw error!;
    sent = answers;
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

  final Completer<void> _checkinCompleter;
  int overviewCalls = 0;

  @override
  Future<void> checkIn(Map<String, String> answers) => _checkinCompleter.future;

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

Future<_FakeRepo> _open(
  WidgetTester tester, {
  Object? error,
  MorningCheckin? existing,
}) async {
  final repo = _FakeRepo()..error = error;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [recoveryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCheckinSheet(context, existing: existing),
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

/// Answers all four questions, so Save is enabled.
Future<void> _answerAll(WidgetTester tester) async {
  for (final key in const [
    'checkin.sleepQuality.poor',
    'checkin.muscleSoreness.severe',
    'checkin.energy.low',
    'checkin.stress.high',
  ]) {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }
}

bool _saveEnabled(WidgetTester tester) {
  final button = tester.widget<FsButton>(find.byKey(const Key('checkin.save')));
  return button.onPressed != null;
}

/// The chip labels of one question's row, left to right then top to bottom.
List<String> _rowLabels(WidgetTester tester, String field) {
  final chips = find.byWidgetPredicate(
    (w) =>
        w is FsChip &&
        (w.key as ValueKey<String>?)?.value.startsWith('checkin.$field.') ==
            true,
  );
  final found = tester.widgetList<FsChip>(chips).toList();
  final positions =
      [for (final c in found) (c.label, tester.getTopLeft(find.byWidget(c)))]
        ..sort((a, b) {
          final dy = a.$2.dy.compareTo(b.$2.dy);
          return dy != 0 ? dy : a.$2.dx.compareTo(b.$2.dx);
        });
  return [for (final p in positions) p.$1];
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

    await _answerAll(tester);
    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();

    // Column spellings, untouched.
    expect(repo.sent!['sleepQuality'], 'poor');
    expect(repo.sent!['muscleSoreness'], 'severe');
    expect(repo.sent!['energy'], 'low');
    expect(repo.sent!['stress'], 'high');
  });

  testWidgets('a failed save says so and does not claim it saved', (
    tester,
  ) async {
    await _open(tester, error: Exception('offline'));

    await _answerAll(tester);
    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(find.byKey(const Key('checkin.save')), findsOneWidget);
  });

  testWidgets(
    'dismissing the sheet mid-save still refreshes the overview once the '
    'save lands',
    (tester) async {
      final completer = Completer<void>();
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

      await _answerAll(tester);
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
      completer.complete();
      await tester.pumpAndSettle();

      // Against the unguarded `ref.invalidate` this call throws inside the
      // disposed sheet's own catch block, `mounted` is false, and the
      // method returns before the overview is ever re-fetched -- this count
      // would stay at 1.
      expect(repo.overviewCalls, 2);
    },
  );

  testWidgets('a new check-in starts with nothing chosen and Save disabled', (
    tester,
  ) async {
    final repo = await _open(tester);

    final chips = tester.widgetList<FsChip>(find.byType(FsChip));
    expect(chips, isNotEmpty);
    expect(chips.where((c) => c.selected), isEmpty);
    expect(_saveEnabled(tester), isFalse);
    // Says why Save is waiting, rather than leaving a dead button.
    expect(find.text('Answer all four to save.'), findsOneWidget);

    // Three of four is still not enough.
    for (final key in const [
      'checkin.sleepQuality.good',
      'checkin.muscleSoreness.none',
      'checkin.energy.high',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }
    expect(_saveEnabled(tester), isFalse);
    await tester.ensureVisible(find.byKey(const Key('checkin.save')));
    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pump();
    expect(repo.sent, isNull);

    await tester.tap(find.byKey(const Key('checkin.stress.very_low')));
    await tester.pump();
    expect(_saveEnabled(tester), isTrue);
    expect(find.text('Answer all four to save.'), findsNothing);
  });

  testWidgets('Update opens on what was answered, ready to save', (
    tester,
  ) async {
    await _open(
      tester,
      existing: const MorningCheckin(
        checkinId: 1,
        checkinDate: '2026-10-18',
        sleepQuality: 'fair',
        muscleSoreness: 'mild',
        energy: 'very_low',
        stress: 'moderate',
      ),
    );

    bool selected(String key) =>
        tester.widget<FsChip>(find.byKey(Key(key))).selected;
    expect(selected('checkin.sleepQuality.fair'), isTrue);
    expect(selected('checkin.muscleSoreness.mild'), isTrue);
    expect(selected('checkin.energy.very_low'), isTrue);
    expect(selected('checkin.stress.moderate'), isTrue);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('every scale runs the same way, worst to best', (tester) async {
    await _open(tester);

    expect(_rowLabels(tester, 'sleepQuality'), [
      'Poor',
      'Fair',
      'Good',
      'Excellent',
    ]);
    expect(_rowLabels(tester, 'muscleSoreness'), [
      'Severe',
      'Moderate',
      'Mild',
      'None',
    ]);
    expect(_rowLabels(tester, 'energy'), [
      'Very low',
      'Low',
      'Moderate',
      'High',
    ]);
    expect(_rowLabels(tester, 'stress'), [
      'High',
      'Moderate',
      'Low',
      'Very low',
    ]);
  });

  testWidgets('it says why it asks', (tester) async {
    await _open(tester);

    expect(
      find.text(
        "Four quick questions. Your answers feed today's injury-risk estimate.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('fits a 320 dp phone at 2x text, Save reachable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repo = await _open(tester);
    expect(tester.takeException(), isNull);

    await _answerAll(tester);
    await tester.ensureVisible(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();
    expect(repo.sent, isNotNull);
  });
}
