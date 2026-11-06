import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show
        bodyWeightProvider,
        profileProvider,
        ProfileNotifier,
        weightUnitProvider;
import 'package:fitsync/features/profile/presentation/widgets/body_weight_card.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/progress_screen.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/widgets/progress_cards.dart';

/// The real numbers off a completed manual workout.
const _mine = SessionHistoryEntry(
  sessionId: 32,
  sessionDate: '2026-09-14',
  setCount: 21,
  exerciseCount: 4,
  durationMin: 2,
  totalVolumeKg: 2953,
);

const _fromPlan = SessionHistoryEntry(
  sessionId: 30,
  sessionDate: '2026-09-12',
  setCount: 12,
  exerciseCount: 6,
  durationMin: 44,
  totalVolumeKg: 5100,
  planName: 'Upper Body · Push',
);

/// A quiet reading with nothing to report -- what most of these tests hand
/// the analytics and summary cards, since they are testing the history list
/// underneath, not the cards themselves.
const _quietAnalytics = TrainingAnalytics(
  period: 'week',
  volume: [VolumeBucket(label: '-1d', volumeKg: 0)],
  change: VolumeChange(totalKg: 0, previousKg: 0, changePct: null),
  adherence: Adherence(done: 0, target: null, weeks: 1),
  muscles: [],
);

/// Sets logged in the window, for the card beside Sessions. Zero unless a
/// test says otherwise -- none of these are about the count itself.
const _quietSummary = TrainingSummary(
  sessionCount: 0,
  setCount: 0,
  totalVolumeKg: 0,
);

const _emptyBodyWeight = BodyWeightSeries(
  widened: false,
  points: [],
  reference: null,
  unit: 'kg',
);

class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({
    this.entries = const [],
    this.analyticsValue = _quietAnalytics,
    this.summaryValue = _quietSummary,
    this.error,
    this.total,
    this.summaryError,
  });

  /// Thrown by [summary] alone: the sets card failing while the rest of the
  /// screen loads.
  final Object? summaryError;

  final List<SessionHistoryEntry> entries;

  /// What the server says it holds in all, when that is more than [entries]
  /// -- null for the same count. Pages are cut from [entries] as the server
  /// cuts them, newest first.
  final int? total;

  final pagesAsked = <int>[];

  /// Thrown by [history] for page 2 and on while set: the first page loads
  /// and an older one fails.
  Object? olderError;

  /// Holds [history] for page 2 and on until completed, while set.
  Completer<void>? olderGate;
  final TrainingAnalytics analyticsValue;
  final TrainingSummary summaryValue;

  /// Thrown by every method below when set -- a systemic outage, the same
  /// shape the old single-provider screen modelled.
  final Object? error;

  final periodsAsked = <String>[];

  @override
  Future<SessionHistoryPage> history({int page = 1, int limit = 20}) async {
    pagesAsked.add(page);
    if (error != null) throw error!;
    if (page > 1) {
      await olderGate?.future;
      if (olderError != null) throw olderError!;
    }
    return SessionHistoryPage(
      sessions: entries.skip((page - 1) * limit).take(limit).toList(),
      total: total ?? entries.length,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<TrainingAnalytics> analytics(String period) async {
    periodsAsked.add(period);
    if (error != null) throw error!;
    return analyticsValue;
  }

  @override
  Future<TrainingSummary> summary({String period = 'week'}) async {
    if (error != null) throw error!;
    if (summaryError != null) throw summaryError!;
    return summaryValue;
  }

  @override
  String get baseUrl => 'http://test.local';

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// Stands in for the profile fetch the volume card's weight unit reads (see
/// `VolumeTrendCard.unit`) -- none of these tests are about units, so this
/// keeps that lookup from ever reaching a real `ApiClient`.
class _StubProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile> build() async => const Profile(
    userId: 1,
    email: 'a@b.c',
    fullName: 'A',
    onboardingCompleted: true,
    isPremium: false,
    notificationsEnabled: true,
    equipment: [],
    injuries: [],
  );
}

Future<FakeSessionRepository> _pump(
  WidgetTester tester, {
  FakeSessionRepository? repo,
  WeightUnit? unit,
  BodyWeightSeries bodyWeight = _emptyBodyWeight,
  Future<BodyWeightSeries> Function()? loadBodyWeight,
}) async {
  final fake = repo ?? FakeSessionRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(fake),
        // The body-weight card is a separate feature's provider; none of these
        // tests are about it, so it is stubbed quiet rather than left to reach
        // a real ApiClient.
        bodyWeightProvider.overrideWith(
          (ref, period) => loadBodyWeight?.call() ?? Future.value(bodyWeight),
        ),
        profileProvider.overrideWith(_StubProfileNotifier.new),
        // Only the unit tests pin it; everyone else reads the stub profile's
        // default, kilograms, exactly as a real account without a choice does.
        if (unit != null) weightUnitProvider.overrideWithValue(unit),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        // Matches how the real app hosts this screen: training_shell.dart
        // wraps every tab in a Scaffold, which is where the Material ancestor
        // for ShareWithCoachCard's own InkWell comes from in production.
        home: const Scaffold(body: ProgressScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('a completed workout is visible at last', (tester) async {
    // The whole reason this screen exists: a manual session completed, was
    // stored with its 21 sets and 2,953 kg, and had nowhere to be seen.
    await _pump(tester, repo: FakeSessionRepository(entries: const [_mine]));

    // skipOffstage: false -- the rebuilt screen leads with four cards above
    // the history list, so in the test viewport this row sits below the
    // fold. See training_shell_test.dart for the same caveat.
    expect(find.text('Your own workout', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('21 sets', skipOffstage: false), findsWidgets);
  });

  testWidgets('the headline reads adherence against the plan', (tester) async {
    // Adherence, not volume, is the hero now -- the one number a beginner
    // can act on in week one, when every trend chart is still one point.
    await _pump(
      tester,
      repo: FakeSessionRepository(
        analyticsValue: const TrainingAnalytics(
          period: 'week',
          volume: [VolumeBucket(label: '-1d', volumeKg: 0)],
          change: VolumeChange(totalKg: 0, previousKg: 0, changePct: null),
          adherence: Adherence(done: 14, target: 16, weeks: 4),
          muscles: [],
        ),
      ),
    );

    expect(find.text('14 / 16'), findsOneWidget);
  });

  testWidgets('the headline is a bare count with no active plan', (
    tester,
  ) async {
    // No plan means no target to divide by -- a denominator nobody agreed
    // to would be fiction, so the card shows the count alone.
    await _pump(
      tester,
      repo: FakeSessionRepository(
        analyticsValue: const TrainingAnalytics(
          period: 'week',
          volume: [VolumeBucket(label: '-1d', volumeKg: 0)],
          change: VolumeChange(totalKg: 0, previousKg: 0, changePct: null),
          adherence: Adherence(done: 3, target: null, weeks: 1),
          muscles: [],
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('/'), findsNothing);
  });

  testWidgets('a plan workout is listed under its plan name', (tester) async {
    await _pump(
      tester,
      repo: FakeSessionRepository(entries: const [_fromPlan]),
    );

    expect(find.text('Upper Body · Push', skipOffstage: false), findsOneWidget);
  });

  testWidgets('changing the window asks the server for it', (tester) async {
    final repo = await _pump(tester, repo: FakeSessionRepository());
    expect(repo.periodsAsked, ['week']);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    expect(repo.periodsAsked.last, 'month');
  });

  // The card names the period it shows ("Last 30 days"), so it has to be
  // told which one the segment picked.
  testWidgets('the body-weight card is told the window', (tester) async {
    await _pump(tester, repo: FakeSessionRepository());
    expect(
      tester.widget<BodyWeightCard>(find.byType(BodyWeightCard)).period,
      'week',
    );

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<BodyWeightCard>(find.byType(BodyWeightCard)).period,
      'month',
    );
  });

  // PS-20: the card's "All weigh-ins" opens the list a weigh-in is deleted
  // from.
  testWidgets('All weigh-ins opens the weigh-ins sheet', (tester) async {
    await _pump(
      tester,
      bodyWeight: const BodyWeightSeries(
        widened: false,
        points: [
          BodyWeightPoint(loggedOn: '2026-09-15', weightKg: 80),
          BodyWeightPoint(loggedOn: '2026-09-16', weightKg: 79.5),
        ],
        reference: null,
        unit: 'kg',
      ),
    );

    final chip = find.byKey(const Key('bodyWeight.entries'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.text('Your weigh-ins'), findsOneWidget);
  });

  testWidgets('nothing trained yet says so plainly', (tester) async {
    // The placeholder this screen replaces said volume "appears here once you
    // have logged a few workouts" -- so a user who HAD logged one went
    // looking for a bug. An empty state must not imply the screen is waiting
    // on the user when it has simply been handed nothing.
    await _pump(tester, repo: FakeSessionRepository(entries: const []));

    expect(
      find.textContaining('No completed workouts yet', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('once you have logged'), findsNothing);
  });

  testWidgets('a failure offers a retry rather than an empty screen', (
    tester,
  ) async {
    // The analytics call is what earns the full-screen retry now -- it owns
    // the period the rest of the screen is scoped to -- so the fake's error
    // has to come from there for this to still exercise that path.
    await _pump(
      tester,
      repo: FakeSessionRepository(
        error: const ApiException(
          'NETWORK_ERROR',
          'Could not reach the server.',
        ),
      ),
    );

    expect(
      find.textContaining(
        "Couldn't reach FitSync. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    // The kit's retry: plain words over a small secondary "Try again", not a
    // Material FilledButton under a cloud.
    expect(find.byType(FsRetry), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(
      find.textContaining('No completed workouts yet'),
      findsNothing,
      reason: 'a failure is not the same as having trained nothing',
    );
  });

  testWidgets("a card's failure uses the kit's Try again, which reloads it", (
    tester,
  ) async {
    var loads = 0;
    await _pump(
      tester,
      loadBodyWeight: () async {
        loads++;
        throw const ApiException('NETWORK_ERROR', 'Could not reach it.');
      },
    );
    final retry = find.descendant(
      of: find.byType(FsRetry),
      matching: find.text('Try again'),
    );
    await tester.scrollUntilVisible(retry, 200);
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    final before = loads;

    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(loads, before + 1);
  });

  // The sets card sits in an IntrinsicHeight row beside Sessions; its
  // failure has to lay out there too, at half the width.
  testWidgets("the sets card's failure fits beside Sessions", (tester) async {
    await _pump(
      tester,
      repo: FakeSessionRepository(
        summaryError: const ApiException('NETWORK_ERROR', 'down'),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(AdherenceCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FsRetry),
        matching: find.text('Try again'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a session that logged no weight does not read as zero', (
    tester,
  ) async {
    // A bodyweight-only workout has no volume. Printing "0 kg" next to it
    // reads as a failure to record rather than as a fact about the workout.
    await _pump(
      tester,
      repo: FakeSessionRepository(
        entries: const [
          SessionHistoryEntry(
            sessionId: 1,
            sessionDate: '2026-09-13',
            setCount: 9,
            exerciseCount: 3,
            durationMin: 20,
          ),
        ],
      ),
    );

    expect(find.textContaining('0 kg'), findsNothing);
    expect(find.textContaining('9 sets', skipOffstage: false), findsWidgets);
  });

  testWidgets(
    'cards render in prototype order: volume, the pair, body weight, muscles',
    (tester) async {
      // The prototype's Progress screen: segment · total volume · sessions and
      // sets side by side · body weight · volume by muscle. Estimated 1RM is
      // not on it at all. A tall viewport keeps every card actually laid out
      // instead of culled below the fold, so their positions are comparable.
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester);

      double dy(Finder f) => tester.getTopLeft(f).dy;

      final volumeDy = dy(find.byType(VolumeTrendCard));
      final sessionsDy = dy(find.byType(AdherenceCard));
      final bodyWeightDy = dy(find.byType(BodyWeightCard));
      final musclesDy = dy(find.text('VOLUME BY MUSCLE'));

      expect(
        volumeDy,
        lessThan(sessionsDy),
        reason: 'the volume chart leads, with the pair beneath it',
      );
      expect(
        sessionsDy,
        lessThan(bodyWeightDy),
        reason: 'sessions and sets sit above body weight',
      );
      expect(
        bodyWeightDy,
        lessThan(musclesDy),
        reason: 'muscles renders last of the analytics cards',
      );

      // Sessions and Sets share a row, so they start at the same height.
      expect(dy(find.byType(SetsCard)), sessionsDy);

      // Estimated 1RM is gone from the screen entirely.
      expect(find.text('ESTIMATED 1RM'), findsNothing);
    },
  );

  testWidgets('the share card sits at the foot of the tab', (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester);

    expect(find.byType(ShareWithCoachCard), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(ShareWithCoachCard)).dy,
      greaterThan(tester.getTopLeft(find.byType(BodyWeightCard)).dy),
      reason: 'the action comes after what it shares',
    );
  });

  testWidgets('a past workout reads its day in words, not as an ISO date', (
    tester,
  ) async {
    await _pump(tester, repo: FakeSessionRepository(entries: const [_mine]));

    expect(find.text('2026-09-14', skipOffstage: false), findsNothing);
    // September 14, 2026 was a Monday.
    expect(
      find.textContaining('Mon, Sep 14', skipOffstage: false),
      findsOneWidget,
    );
  });

  group('older workouts', () {
    List<SessionHistoryEntry> many(int n) => [
      for (var i = 0; i < n; i++)
        SessionHistoryEntry(
          sessionId: 100 - i,
          sessionDate: '2026-08-${(28 - i).toString().padLeft(2, '0')}',
          setCount: i + 1,
          exerciseCount: 1,
          planName: 'Workout ${i + 1}',
        ),
    ];

    testWidgets('past the newest 20, a button loads the next page', (
      tester,
    ) async {
      final repo = FakeSessionRepository(entries: many(23));
      await _pump(tester, repo: repo);

      final more = find.text('Show older workouts', skipOffstage: false);
      expect(more, findsOneWidget);
      expect(find.text('Workout 21', skipOffstage: false), findsNothing);

      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(repo.pagesAsked, contains(2));
      expect(find.text('Workout 21', skipOffstage: false), findsOneWidget);
      expect(find.text('Workout 23', skipOffstage: false), findsOneWidget);
      // Everything is on screen now, so there is nothing older to offer.
      expect(more, findsNothing);
    });

    Future<void> showOlder(WidgetTester tester) async {
      // Scrolled to, not ensureVisible: on a short screen the list has not
      // built the history yet.
      final more = find.text('Show older workouts');
      await tester.scrollUntilVisible(
        more,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(more);
    }

    // The history is one child of the tab's ListView, which drops it once it
    // is scrolled far enough away. The pages already read must still be
    // there when it comes back, not fetched again behind a spinner.
    testWidgets('scrolling far away and back does not fetch them again', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeSessionRepository(entries: many(23));
      await _pump(tester, repo: repo);
      await showOlder(tester);
      await tester.pumpAndSettle();
      expect(repo.pagesAsked.where((p) => p == 2), hasLength(1));

      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, 20000));
      await tester.pumpAndSettle();
      // Gone from the tree, not merely off screen.
      expect(find.text('Workout 23', skipOffstage: false), findsNothing);

      await tester.drag(list, const Offset(0, -20000));
      await tester.pump();
      expect(find.text('Workout 23', skipOffstage: false), findsOneWidget);
      await tester.pumpAndSettle();
      expect(repo.pagesAsked.where((p) => p == 2), hasLength(1));
    });

    testWidgets('an older page still on its way shows a spinner in its place', (
      tester,
    ) async {
      final repo = FakeSessionRepository(entries: many(23));
      final gate = repo.olderGate = Completer<void>();
      await _pump(tester, repo: repo);
      await showOlder(tester);
      await tester.pump();

      final spinner = find.byType(
        CircularProgressIndicator,
        skipOffstage: false,
      );
      expect(spinner, findsOneWidget);
      expect(
        find.text('Show older workouts', skipOffstage: false),
        findsNothing,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(spinner, findsNothing);
      expect(find.text('Workout 23', skipOffstage: false), findsOneWidget);
    });

    testWidgets("an older page's failure keeps the rows and offers Try again", (
      tester,
    ) async {
      final repo = FakeSessionRepository(entries: many(23))
        ..olderError = const ApiException('NETWORK_ERROR', 'offline');
      await _pump(tester, repo: repo);
      await showOlder(tester);
      await tester.pumpAndSettle();

      // The first page stays; only the tail says what went wrong.
      expect(find.text('Workout 20', skipOffstage: false), findsOneWidget);
      expect(find.text('Workout 21', skipOffstage: false), findsNothing);
      final again = find.text('Try again', skipOffstage: false);
      expect(again, findsOneWidget);
      expect(
        find.text('Show older workouts', skipOffstage: false),
        findsNothing,
      );

      repo.olderError = null;
      await tester.ensureVisible(again);
      await tester.pumpAndSettle();
      await tester.tap(again);
      await tester.pumpAndSettle();

      expect(again, findsNothing);
      expect(find.text('Workout 23', skipOffstage: false), findsOneWidget);
    });

    // An older page kept from before page 1 was fetched again is out of
    // date: a newer workout pushed every row down one. Shown while its own
    // refetch runs, it would miss the row at the page edge (or repeat one,
    // or after a sign-out show the last account's workouts).
    testWidgets('an older page refetched after page 1 shows a spinner, '
        'never its old rows', (tester) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeSessionRepository(entries: many(23));
      await _pump(tester, repo: repo);
      await showOlder(tester);
      await tester.pumpAndSettle();
      expect(find.text('Workout 21', skipOffstage: false), findsOneWidget);

      // Scrolled away, so page 2 has no listener while page 1 refreshes.
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, 20000));
      await tester.pumpAndSettle();
      expect(find.text('Workout 21', skipOffstage: false), findsNothing);

      repo.entries.insert(
        0,
        const SessionHistoryEntry(
          sessionId: 200,
          sessionDate: '2026-08-29',
          setCount: 1,
          exerciseCount: 1,
          planName: 'Newest',
        ),
      );
      final gate = repo.olderGate = Completer<void>();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProgressScreen)),
      );
      container.invalidate(sessionHistoryProvider);
      await tester.runAsync(
        () => container.read(sessionHistoryProvider.future),
      );
      await tester.pumpAndSettle();

      await tester.drag(list, const Offset(0, -20000));
      await tester.pumpAndSettle();
      await showOlder(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Workout 21', skipOffstage: false), findsNothing);
      expect(
        find.byType(CircularProgressIndicator, skipOffstage: false),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();
      for (final n in [20, 21, 22, 23]) {
        expect(find.text('Workout $n', skipOffstage: false), findsOneWidget);
      }
    });

    test('a fresh first page drops the older pages shown', () async {
      // A finished workout refetches page 1 and shifts every older row by
      // one, so pages fetched before it would repeat a workout.
      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(
            FakeSessionRepository(entries: many(23)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(historyPagesProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(sessionHistoryProvider.future);

      container.read(historyPagesProvider.notifier).showMore();
      expect(container.read(historyPagesProvider), 2);

      container.invalidate(sessionHistoryProvider);
      await container.read(sessionHistoryProvider.future);
      expect(container.read(historyPagesProvider), 1);
    });

    testWidgets('no button when the first page holds every workout', (
      tester,
    ) async {
      await _pump(tester, repo: FakeSessionRepository(entries: many(20)));

      expect(
        find.text('Show older workouts', skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('history volume follows the weight unit', () {
    const heavy = SessionHistoryEntry(
      sessionId: 40,
      sessionDate: '2026-09-15',
      setCount: 10,
      exerciseCount: 3,
      durationMin: 30,
      totalVolumeKg: 1000,
    );

    testWidgets('a pound user reads pounds, rounded to the whole pound', (
      tester,
    ) async {
      // 1000 kg is 2,204.62 lb; history shows whole numbers, so 2,205.
      await _pump(
        tester,
        repo: FakeSessionRepository(entries: const [heavy]),
        unit: WeightUnit.lb,
      );

      expect(
        find.textContaining('2,205 lb', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('1,000 kg', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('a kilogram user sees exactly what they did before', (
      tester,
    ) async {
      await _pump(
        tester,
        repo: FakeSessionRepository(entries: const [heavy]),
        unit: WeightUnit.kg,
      );

      expect(
        find.text('10 sets · 1,000 kg · 30 min', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a bodyweight-only session shows no volume in pounds either', (
      tester,
    ) async {
      await _pump(
        tester,
        repo: FakeSessionRepository(
          entries: const [
            SessionHistoryEntry(
              sessionId: 1,
              sessionDate: '2026-09-13',
              setCount: 9,
              exerciseCount: 3,
              durationMin: 20,
            ),
          ],
        ),
        unit: WeightUnit.lb,
      );

      expect(find.text('9 sets · 20 min', skipOffstage: false), findsOneWidget);
      expect(find.textContaining(' lb', skipOffstage: false), findsNothing);
    });

    testWidgets('the volume chart plots pounds for a pound user', (
      tester,
    ) async {
      // The chart has no axis labels, but its touch tooltip reads the raw y
      // value -- so a pound user tapping a point would otherwise get kilos.
      await _pump(
        tester,
        repo: FakeSessionRepository(
          analyticsValue: const TrainingAnalytics(
            period: 'week',
            volume: [
              VolumeBucket(label: '-1d', volumeKg: 0),
              VolumeBucket(label: 'Today', volumeKg: 1000),
            ],
            change: VolumeChange(totalKg: 1000, previousKg: 0, changePct: null),
            adherence: Adherence(done: 1, target: null, weeks: 1),
            muscles: [],
          ),
        ),
        unit: WeightUnit.lb,
      );

      final chart = tester.widget<FsBarChart>(
        find.descendant(
          of: find.byType(VolumeTrendCard),
          matching: find.byType(FsBarChart),
        ),
      );
      expect(chart.bars.last.value, closeTo(2204.62, 0.01));
      expect(find.text('lb lifted'), findsOneWidget);
    });

    testWidgets('body weight follows the unit switch, not the cached series', (
      tester,
    ) async {
      // The series was fetched while the user was on kilograms, and the
      // provider keeps it alive; switching to pounds refetches nothing, so
      // the card has to take the unit the rest of the screen reads.
      await _pump(
        tester,
        bodyWeight: const BodyWeightSeries(
          widened: false,
          points: [BodyWeightPoint(loggedOn: '2026-09-15', weightKg: 80)],
          reference: null,
          unit: 'kg',
        ),
        unit: WeightUnit.lb,
      );

      expect(
        find.text(formatWeightWithUnit(80, WeightUnit.lb), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('80 kg', skipOffstage: false), findsNothing);
    });

    testWidgets('pound history fits a 320 dp screen at double text size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 6000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pump(
        tester,
        repo: FakeSessionRepository(
          entries: const [
            SessionHistoryEntry(
              sessionId: 41,
              sessionDate: '2026-09-15',
              setCount: 24,
              exerciseCount: 6,
              durationMin: 75,
              totalVolumeKg: 45359.237,
            ),
          ],
        ),
        unit: WeightUnit.lb,
      );

      expect(
        find.textContaining('100,000 lb', skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
