import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show injuryOptionsProvider;
import 'package:fitsync/features/recovery/data/recovery_repository.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart';
import 'package:fitsync/features/recovery/presentation/widgets/checkin_sheet.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/session_outcome.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart'
    show pendingOutcomeProvider, sessionRepositoryProvider;

class _FakeRepo implements RecoveryRepository {
  _FakeRepo([this.log]);

  /// Shared with [_FakeSessions], so a test can see which request went first.
  final List<String>? log;
  Map<String, String>? sent;
  Object? error;

  @override
  Future<void> checkIn(Map<String, String> answers) async {
    log?.add('checkin');
    if (error != null) throw error!;
    sent = answers;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// Records every pain answer posted, in the shared [log].
class _FakeSessions implements SessionRepository {
  _FakeSessions([List<String>? log]) : log = log ?? [];

  final List<String> log;
  final outcomes = <({int sessionId, String painLevel, int? injuryId})>[];
  Object? error;

  @override
  Future<void> recordOutcome(
    int sessionId, {
    required String painLevel,
    int? injuryId,
  }) async {
    log.add('outcome');
    if (error != null) throw error!;
    outcomes.add((
      sessionId: sessionId,
      painLevel: painLevel,
      injuryId: injuryId,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// 2026-09-21 is a Monday, and never yesterday again.
const _pending = PendingOutcome(
  sessionId: 7,
  sessionDate: '2026-09-21',
  planName: 'Upper Body · Push',
);

const _regions = [
  InjuryOption(
    injuryId: 1,
    name: 'Shoulder',
    isLateral: true,
    regionGroup: 'upper_body',
  ),
  InjuryOption(
    injuryId: 13,
    name: 'Knee',
    isLateral: true,
    regionGroup: 'lower_body',
  ),
];

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
  PendingOutcome? pending,
  _FakeSessions? sessions,
  List<String>? log,
  VoidCallback? onPendingLookup,
  int regionsFailures = 0,
  Future<PendingOutcome?> Function()? pendingLookup,
  Future<void> Function(ProviderContainer container)? beforeOpen,
}) async {
  final repo = _FakeRepo(log)..error = error;
  var regionsCalls = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recoveryRepositoryProvider.overrideWithValue(repo),
        sessionRepositoryProvider.overrideWithValue(
          sessions ?? _FakeSessions(log),
        ),
        pendingOutcomeProvider.overrideWith((ref) async {
          onPendingLookup?.call();
          if (pendingLookup != null) return pendingLookup();
          return pending;
        }),
        injuryOptionsProvider.overrideWith((ref) async {
          if (regionsCalls++ < regionsFailures) {
            throw Exception("Couldn't load body regions.");
          }
          return _regions;
        }),
      ],
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
  if (beforeOpen != null) {
    await beforeOpen(
      ProviderScope.containerOf(tester.element(find.text('open'))),
    );
    await tester.pump();
  }
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

bool _chipSelected(WidgetTester tester, String key) =>
    tester.widget<FsChip>(find.byKey(Key(key))).selected;

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

  testWidgets('a failed save is spoken to a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, error: Exception('offline'));

    await _answerAll(tester);
    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();

    // A live region, so TalkBack and VoiceOver read the failure out when it
    // appears rather than leaving the user to believe it saved.
    final error = find.text('Something went wrong. Please try again.');
    expect(error, findsOneWidget);
    expect(
      tester.getSemantics(error),
      isSemantics(
        isLiveRegion: true,
        label: 'Something went wrong. Please try again.',
      ),
    );
    semantics.dispose();
  });

  testWidgets(
    'dismissing the sheet mid-save still refreshes the overview once the '
    'save lands',
    (tester) async {
      final completer = Completer<void>();
      final repo = _SlowFakeRepo(completer);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recoveryRepositoryProvider.overrideWithValue(repo),
            pendingOutcomeProvider.overrideWith((ref) async => null),
          ],
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

  testWidgets(
    'a save that fails after the sheet was dismissed says so on the screen '
    'underneath',
    (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recoveryRepositoryProvider.overrideWithValue(
              _SlowFakeRepo(completer),
            ),
            pendingOutcomeProvider.overrideWith((ref) async => null),
          ],
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

      await _answerAll(tester);
      await tester.tap(find.byKey(const Key('checkin.save')));
      await tester.pump();
      // Dismissed while the save is in flight.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Morning check-in'), findsNothing);

      completer.completeError(Exception('offline'));
      await tester.pumpAndSettle();

      // The sheet's own error line went with the sheet, so the failure is
      // said where the user now is, rather than not at all.
      expect(
        find.text(
          "Your check-in wasn't saved. Something went wrong. Please try "
          'again.',
        ),
        findsOneWidget,
      );
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

  testWidgets('every answer has a full-size tap band', (tester) async {
    final repo = await _open(tester);

    final targets = find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> &&
          key.value.startsWith('checkin.') &&
          key.value.endsWith('.target');
    });
    expect(targets, findsNWidgets(16));
    for (final target in targets.evaluate()) {
      final size = (target.renderObject! as RenderBox).size;
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }

    // A tap in the band but outside the pill still answers.
    final band = find.byKey(const Key('checkin.sleepQuality.poor.target'));
    final chip = find.byKey(const Key('checkin.sleepQuality.poor'));
    expect(
      tester.getSize(band).height,
      greaterThan(tester.getSize(chip).height),
    );
    await tester.tapAt(tester.getTopLeft(band) + const Offset(24, 2));
    await tester.pump();
    expect(tester.widget<FsChip>(chip).selected, isTrue);
    expect(repo.sent, isNull);
  });

  testWidgets('each answer is named with its question for a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester);

    expect(find.bySemanticsLabel('Sleep: Poor'), findsOneWidget);
    expect(find.bySemanticsLabel('Soreness: Very sore'), findsNothing);
    expect(find.bySemanticsLabel('Soreness: Severe'), findsOneWidget);
    expect(find.bySemanticsLabel('Energy: Very low'), findsOneWidget);
    expect(find.bySemanticsLabel('Stress: Moderate'), findsOneWidget);
    // Not the bare answer, which "Moderate" alone would leave ambiguous.
    expect(find.bySemanticsLabel('Moderate'), findsNothing);

    SemanticsData poor() => tester
        .getSemantics(find.bySemanticsLabel('Sleep: Poor'))
        .getSemanticsData();
    expect(poor().flagsCollection.isButton, isTrue);
    expect(poor().hasAction(SemanticsAction.tap), isTrue);
    // One answer per question: a radio group, as the outcome sheet's.
    expect(poor().flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(poor().flagsCollection.isChecked, CheckedState.isFalse);
    expect(poor().flagsCollection.isSelected, Tristate.none);

    await tester.tap(find.byKey(const Key('checkin.sleepQuality.poor')));
    await tester.pump();
    expect(poor().flagsCollection.isChecked, CheckedState.isTrue);
    expect(poor().flagsCollection.isSelected, Tristate.none);
    semantics.dispose();
  });

  testWidgets('it says why it asks', (tester) async {
    await _open(tester);

    expect(find.text("Helps estimate today's injury risk."), findsOneWidget);
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

  testWidgets(
    'at its fullest the sheet stops short of the status bar, the tab still '
    'showing above it',
    (tester) async {
      // A small phone with a status bar, at large text, with the pain
      // question and its regions open: more than the screen holds.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _open(tester, pending: _pending);
      await _tapKey(tester, 'checkin.pain.mild');
      expect(tester.takeException(), isNull);

      // As the How to read sheet does: 90% of the screen at most.
      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.top, greaterThanOrEqualTo(640 * 0.1 - 0.5));
    },
  );

  group('like its sibling sheet', () {
    testWidgets('it has a drag handle and a heading', (tester) async {
      final semantics = tester.ensureSemantics();
      await _open(tester);

      expect(find.byKey(const Key('checkin.handle')), findsOneWidget);
      // P-19/P-23: the kit's handle, drag claim and height cap, not copies.
      expect(
        tester.widget(find.byKey(const Key('checkin.handle'))),
        isA<FsSheetHandle>(),
      );
      expect(find.byType(FsSheetDiscardGuard), findsOneWidget);
      expect(find.byType(FsSheetHeightCap), findsOneWidget);
      // Its own, inside the discard guard, and not Material's as well:
      // Material's sits outside the sheet's child, where a drag on it would
      // close the sheet without asking (PT-22).
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
      );
      expect(
        tester.getSemantics(find.text('Morning check-in')),
        matchesSemantics(label: 'Morning check-in', isHeader: true),
      );
      semantics.dispose();
    });

    testWidgets('Cancel closes it, so closing never depends on a swipe', (
      tester,
    ) async {
      final repo = await _open(tester);

      await _tapKey(tester, 'checkin.cancel');

      expect(find.text('Morning check-in'), findsNothing);
      expect(repo.sent, isNull);
    });

    testWidgets('Cancel is off while a save is in flight', (tester) async {
      // Cancel mid-save closed the sheet and the check-in saved anyway, so
      // the button said Cancel without cancelling anything.
      final completer = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recoveryRepositoryProvider.overrideWithValue(
              _SlowFakeRepo(completer),
            ),
            pendingOutcomeProvider.overrideWith((ref) async => null),
          ],
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
      await _answerAll(tester);
      await tester.ensureVisible(find.byKey(const Key('checkin.save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('checkin.save')));
      await tester.pump();

      final cancel = tester.widget<FsButton>(
        find.byKey(const Key('checkin.cancel')),
      );
      expect(cancel.onPressed, isNull);
      await tester.ensureVisible(find.byKey(const Key('checkin.cancel')));
      await tester.tap(
        find.byKey(const Key('checkin.cancel')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Morning check-in'), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Cancel with answers given asks first', (tester) async {
      await _open(tester);
      await _tapKey(tester, 'checkin.sleepQuality.good');

      await _tapKey(tester, 'checkin.cancel');

      expect(find.text('Discard your changes?'), findsOneWidget);
    });
  });

  group('closing with answers given', () {
    testWidgets('back with nothing answered closes without asking', (
      tester,
    ) async {
      await _open(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Morning check-in'), findsNothing);
    });

    testWidgets('back asks first, and Keep editing keeps the answers', (
      tester,
    ) async {
      await _open(tester);
      await _tapKey(tester, 'checkin.sleepQuality.good');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('discard.keep')));
      await tester.pumpAndSettle();
      expect(find.text('Morning check-in'), findsOneWidget);
      expect(_chipSelected(tester, 'checkin.sleepQuality.good'), isTrue);
    });

    testWidgets('Discard closes the sheet without saving', (tester) async {
      final repo = await _open(tester);
      await _answerAll(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard.confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Morning check-in'), findsNothing);
      expect(repo.sent, isNull);
    });

    testWidgets('a tap on the scrim asks first', (tester) async {
      await _open(tester);
      await _tapKey(tester, 'checkin.energy.high');

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsOneWidget);
    });

    testWidgets('a swipe down with nothing answered just closes', (
      tester,
    ) async {
      final repo = await _open(tester);

      // From the handle: on a sheet taller than the test screen, a swipe on
      // the questions scrolls them instead, as on a phone.
      await tester.fling(
        find.byKey(const Key('checkin.handle')),
        const Offset(0, 300),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Morning check-in'), findsNothing);
      expect(repo.sent, isNull);
    });

    testWidgets('a swipe down asks first rather than closing', (tester) async {
      await _open(tester);
      await _tapKey(tester, 'checkin.energy.high');

      await tester.fling(
        find.text('Morning check-in'),
        const Offset(0, 300),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard.keep')));
      await tester.pumpAndSettle();
      expect(find.text('Morning check-in'), findsOneWidget);
      expect(_chipSelected(tester, 'checkin.energy.high'), isTrue);
    });

    testWidgets(
      'a screen reader is not offered a scroll that opens the question',
      (tester) async {
        final semantics = tester.ensureSemantics();
        // A small phone at large text, so the sheet really does scroll: its
        // own scroll is offered, and that is all a scroll gesture may reach.
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _open(tester);
        await _tapKey(tester, 'checkin.energy.high');

        // The swipe-down guard must not surface as scroll actions of its
        // own, which a screen reader's scroll gesture would run straight
        // into the discard question. Every scroll action on offer is run,
        // both ways, and none of them may ask.
        final scrollable = <SemanticsNode>[];
        void visit(SemanticsNode node) {
          final data = node.getSemanticsData();
          if (data.hasAction(SemanticsAction.scrollDown) ||
              data.hasAction(SemanticsAction.scrollUp)) {
            scrollable.add(node);
          }
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        final owner = tester
            .renderObject(find.text('Morning check-in'))
            .owner!
            .semanticsOwner!;
        visit(owner.rootSemanticsNode!);
        expect(scrollable, isNotEmpty, reason: 'the sheet scrolls here');
        for (final node in scrollable) {
          for (final action in const [
            SemanticsAction.scrollUp,
            SemanticsAction.scrollDown,
          ]) {
            if (node.getSemanticsData().hasAction(action)) {
              owner.performAction(node.id, action);
              await tester.pumpAndSettle();
            }
          }
        }

        expect(find.text('Discard your changes?'), findsNothing);
        expect(find.text('Morning check-in'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets('a pain answer alone counts as something to lose', (
      tester,
    ) async {
      await _open(tester, pending: _pending);
      await _tapKey(tester, 'checkin.pain.none');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsOneWidget);
    });

    testWidgets('an unchanged Update closes without asking', (tester) async {
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

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Morning check-in'), findsNothing);
    });

    testWidgets('a changed Update asks first, and changing it back does not', (
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
      await _tapKey(tester, 'checkin.energy.high');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('discard.keep')));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'checkin.energy.very_low');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Morning check-in'), findsNothing);
    });
  });

  group('pain row', () {
    test('painRowHeading names the day', () {
      expect(
        painRowHeading('2026-10-20', '2026-10-21'),
        "After yesterday's workout",
      );
      expect(
        painRowHeading('2026-10-19', '2026-10-21'),
        "After Monday's workout",
      );
      expect(
        painRowHeading('2026-10-14', '2026-10-21'),
        "After last Wednesday's workout",
      );
    });

    testWidgets('no pending workout, no pain row', (tester) async {
      await _open(tester);

      expect(find.text('Any pain since?'), findsNothing);
      expect(find.text("Helps estimate today's injury risk."), findsOneWidget);
    });

    testWidgets('no pain row while the lookup is still loading', (
      tester,
    ) async {
      final never = Completer<PendingOutcome?>();
      final repo = await _open(tester, pendingLookup: () => never.future);

      expect(find.text('Any pain since?'), findsNothing);
      expect(find.text("Helps estimate today's injury risk."), findsOneWidget);
      // Lets the lookup's time limits run out, so no timer outlives the test.
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Any pain since?'), findsNothing);

      await _answerAll(tester);
      await _tapKey(tester, 'checkin.save');
      expect(repo.sent, isNotNull);
    });

    testWidgets('no pain row when the lookup fails', (tester) async {
      final repo = await _open(
        tester,
        pendingLookup: () async => throw Exception('offline'),
      );

      expect(find.text('Any pain since?'), findsNothing);
      await _answerAll(tester);
      await _tapKey(tester, 'checkin.save');
      expect(repo.sent, isNotNull);
    });

    testWidgets('a workout that became askable overnight gets its row', (
      tester,
    ) async {
      PendingOutcome? answer;
      await _open(
        tester,
        pendingLookup: () async => answer,
        beforeOpen: (container) async {
          // Yesterday's settled answer: nothing to ask about.
          expect(await container.read(pendingOutcomeProvider.future), isNull);
          // Past midnight the workout is askable, and DayRollover
          // invalidates the cached answer.
          answer = _pending;
          container.invalidate(pendingOutcomeProvider);
        },
      );

      expect(find.text('Any pain since?'), findsOneWidget);
    });

    testWidgets('a pending workout adds an optional row with nothing chosen', (
      tester,
    ) async {
      await _open(tester, pending: _pending);

      expect(find.text("After Monday's workout · optional"), findsOneWidget);
      expect(find.text('Any pain since?'), findsOneWidget);
      expect(find.text("Helps estimate today's injury risk."), findsOneWidget);
      for (final level in painLevels) {
        expect(_chipSelected(tester, 'checkin.pain.$level'), isFalse);
      }
      expect(find.text('Where?'), findsNothing);
    });

    testWidgets('the four answers alone still save, with no pain request', (
      tester,
    ) async {
      final log = <String>[];
      final sessions = _FakeSessions(log);
      await _open(tester, pending: _pending, sessions: sessions, log: log);

      await _answerAll(tester);
      await _tapKey(tester, 'checkin.save');

      expect(log, ['checkin']);
      expect(sessions.outcomes, isEmpty);
    });

    testWidgets('Where? appears with pain, and None clears the region', (
      tester,
    ) async {
      await _open(tester, pending: _pending);

      await _tapKey(tester, 'checkin.pain.mild');
      expect(find.text('Where?'), findsOneWidget);
      await _tapKey(tester, 'checkin.region.13');
      expect(_chipSelected(tester, 'checkin.region.13'), isTrue);

      await _tapKey(tester, 'checkin.pain.none');
      expect(find.text('Where?'), findsNothing);

      await _tapKey(tester, 'checkin.pain.mild');
      expect(_chipSelected(tester, 'checkin.region.13'), isFalse);
    });

    testWidgets('pain without a region blocks Save and says how to skip', (
      tester,
    ) async {
      await _open(tester, pending: _pending);
      await _answerAll(tester);

      await _tapKey(tester, 'checkin.pain.moderate');
      expect(_saveEnabled(tester), isFalse);
      expect(
        find.text(
          'Pick where it hurts, or tap Moderate again to skip this question.',
        ),
        findsOneWidget,
      );

      await _tapKey(tester, 'checkin.pain.moderate');
      expect(_chipSelected(tester, 'checkin.pain.moderate'), isFalse);
      expect(_saveEnabled(tester), isTrue);
      expect(find.byKey(const Key('checkin.hint')), findsNothing);
    });

    testWidgets('the pain answer is saved first, with its region', (
      tester,
    ) async {
      final log = <String>[];
      final sessions = _FakeSessions(log);
      var lookups = 0;
      await _open(
        tester,
        pending: _pending,
        sessions: sessions,
        log: log,
        onPendingLookup: () => lookups++,
      );
      expect(lookups, 1);

      await _answerAll(tester);
      await _tapKey(tester, 'checkin.pain.moderate');
      await _tapKey(tester, 'checkin.region.13');
      await _tapKey(tester, 'checkin.save');

      expect(log, ['outcome', 'checkin']);
      expect(sessions.outcomes, [
        (sessionId: 7, painLevel: 'moderate', injuryId: 13),
      ]);
      expect(find.text('Morning check-in'), findsNothing);
      expect(lookups, 2, reason: 'a stored answer refreshes the pending one');
    });

    testWidgets('None is saved without a region', (tester) async {
      final sessions = _FakeSessions();
      await _open(tester, pending: _pending, sessions: sessions);

      await _answerAll(tester);
      await _tapKey(tester, 'checkin.pain.none');
      await _tapKey(tester, 'checkin.save');

      expect(sessions.outcomes, [
        (sessionId: 7, painLevel: 'none', injuryId: null),
      ]);
    });

    testWidgets('an answer already stored elsewhere counts as saved', (
      tester,
    ) async {
      final log = <String>[];
      final sessions = _FakeSessions(log)
        ..error = const ApiException('OUTCOME_EXISTS', 'x');
      var lookups = 0;
      await _open(
        tester,
        pending: _pending,
        sessions: sessions,
        log: log,
        onPendingLookup: () => lookups++,
      );
      expect(lookups, 1);

      await _answerAll(tester);
      await _tapKey(tester, 'checkin.pain.none');
      await _tapKey(tester, 'checkin.save');

      expect(log, ['outcome', 'checkin']);
      expect(find.text('Morning check-in'), findsNothing);
      expect(find.text(painNotSavedMessage), findsNothing);
      expect(lookups, 2, reason: 'a 409 counts as saved and refreshes');
    });

    testWidgets('a failed pain answer still saves the check-in, then says so', (
      tester,
    ) async {
      final sessions = _FakeSessions()
        ..error = const ApiException('INTERNAL', 'x');
      final repo = await _open(tester, pending: _pending, sessions: sessions);

      await _answerAll(tester);
      await _tapKey(tester, 'checkin.pain.none');
      await _tapKey(tester, 'checkin.save');

      expect(repo.sent, isNotNull);
      expect(find.text('Morning check-in'), findsNothing);
      expect(find.text(painNotSavedMessage), findsOneWidget);
    });

    testWidgets('a failed check-in does not resend a saved pain answer', (
      tester,
    ) async {
      final log = <String>[];
      final sessions = _FakeSessions(log);
      final repo = await _open(
        tester,
        pending: _pending,
        sessions: sessions,
        log: log,
        error: Exception('offline'),
      );

      await _answerAll(tester);
      await _tapKey(tester, 'checkin.pain.none');
      await _tapKey(tester, 'checkin.save');
      expect(log, ['outcome', 'checkin']);
      expect(find.text('Morning check-in'), findsOneWidget);

      // The stored answer cannot change from here, so no dead chips stay.
      expect(find.text("After Monday's workout · optional"), findsOneWidget);
      expect(find.text('Pain answer saved.'), findsOneWidget);
      expect(find.text('Any pain since?'), findsNothing);
      expect(find.byKey(const Key('checkin.pain.none')), findsNothing);

      repo.error = null;
      await _tapKey(tester, 'checkin.save');

      expect(log, ['outcome', 'checkin', 'checkin']);
      expect(sessions.outcomes, hasLength(1));
    });

    testWidgets('Where? offers a retry when regions fail to load', (
      tester,
    ) async {
      await _open(tester, pending: _pending, regionsFailures: 1);

      await _tapKey(tester, 'checkin.pain.mild');
      // The kit's retry: the reason, then "Try again", as elsewhere.
      final retry = tester.widget<FsRetry>(find.byType(FsRetry));
      expect(retry.message, "Couldn't load body regions.");
      expect(find.text("Couldn't load body regions."), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('checkin.regions.retry')),
          matching: find.text('Try again'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const Key('checkin.regions.retry'))).height,
        greaterThanOrEqualTo(48),
      );

      await _tapKey(tester, 'checkin.regions.retry');
      expect(find.byKey(const Key('checkin.region.13')), findsOneWidget);
    });

    testWidgets('each pain answer is named for a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, pending: _pending);
      await _tapKey(tester, 'checkin.pain.mild');

      SemanticsData data(String label) =>
          tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
      // The outcome sheet's same question, said the same way: one answer
      // per row, "radio button, checked".
      final mild = data('Any pain since: Mild');
      expect(mild.flagsCollection.isButton, isTrue);
      expect(mild.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(mild.flagsCollection.isChecked, CheckedState.isTrue);
      expect(mild.flagsCollection.isSelected, Tristate.none);
      expect(
        data('Any pain since: None').flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      final knee = data('Where: Knee');
      expect(knee.flagsCollection.isButton, isTrue);
      expect(knee.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(knee.flagsCollection.isChecked, CheckedState.isFalse);
      expect(knee.flagsCollection.isSelected, Tristate.none);
      semantics.dispose();
    });

    testWidgets('every pain and region answer has a full-size tap band', (
      tester,
    ) async {
      await _open(tester, pending: _pending);
      await _tapKey(tester, 'checkin.pain.mild');

      for (final key in [
        for (final level in painLevels) 'checkin.pain.$level.target',
        'checkin.region.13.target',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
      }
    });

    testWidgets('fits a 320 dp phone at 2x text with the pain row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final sessions = _FakeSessions();
      final repo = await _open(tester, pending: _pending, sessions: sessions);
      expect(tester.takeException(), isNull);

      await _answerAll(tester);
      await _tapKey(tester, 'checkin.pain.severe');
      await _tapKey(tester, 'checkin.region.1');
      expect(tester.takeException(), isNull);
      await _tapKey(tester, 'checkin.save');

      expect(repo.sent, isNotNull);
      expect(sessions.outcomes, hasLength(1));
    });
  });
}
