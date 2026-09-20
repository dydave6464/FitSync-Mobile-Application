import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show bodyWeightProvider, profileProvider, ProfileNotifier;
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
  });

  final List<SessionHistoryEntry> entries;
  final TrainingAnalytics analyticsValue;
  final TrainingSummary summaryValue;

  /// Thrown by every method below when set -- a systemic outage, the same
  /// shape the old single-provider screen modelled.
  final Object? error;

  final periodsAsked = <String>[];

  @override
  Future<SessionHistoryPage> history({int page = 1, int limit = 20}) async {
    if (error != null) throw error!;
    return SessionHistoryPage(
      sessions: entries,
      total: entries.length,
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
          (ref, period) async => _emptyBodyWeight,
        ),
        profileProvider.overrideWith(_StubProfileNotifier.new),
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

    expect(find.textContaining('Could not reach the server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.textContaining('No completed workouts yet'),
      findsNothing,
      reason: 'a failure is not the same as having trained nothing',
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
}
