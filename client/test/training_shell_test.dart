import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart'
    show exerciseDetailProvider;
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show bodyWeightProvider, profileProvider, ProfileNotifier;
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_logger_screen.dart';
import 'package:fitsync/features/plans/presentation/generator_screen.dart';
import 'package:fitsync/features/training/presentation/training_shell.dart';

/// A quiet, zero-everything analytics reading. What every Progress-tab
/// provider below is stubbed to, since this file is about the tab bar, not
/// about what the Progress tab renders once it has real data -- that is
/// progress_screen_test.dart's job.
const _emptyAnalytics = TrainingAnalytics(
  period: 'week',
  volume: [VolumeBucket(label: '-1d', volumeKg: 0)],
  change: VolumeChange(totalKg: 0, previousKg: 0, changePct: null),
  adherence: Adherence(done: 0, target: null, weeks: 1),
  muscles: [],
);

const _emptySummary = TrainingSummary(
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

const _plan = WorkoutPlan(
  planId: 42,
  name: 'Week 1 — Full body',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [
    PlanExercise(
      planExerciseId: 601,
      exerciseId: 101,
      name: 'Goblet squat',
      muscleGroup: 'quadriceps',
      orderNo: 1,
      targetSets: 3,
      targetReps: '8-12',
    ),
  ],
);

/// Stands in for the profile fetch the volume card's weight unit reads (see
/// `VolumeTrendCard.unit`) -- this file is about the tab bar, not units, so
/// this keeps that lookup from ever reaching a real `ApiClient`.
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

Future<void> _pump(WidgetTester tester, {ActiveSession? session}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => _plan),
        activeSessionProvider.overrideWith(() => _StubController(session)),
        completedDaysProvider.overrideWith((ref) async => const <String>{}),
        // The Progress tab is built eagerly with the rest of the shell. Stubbed
        // at the provider rather than the repository: this file is about the
        // tab bar, and Progress has its own test.
        trainingAnalyticsProvider.overrideWith(
          (ref, period) async => _emptyAnalytics,
        ),
        trainingSummaryProvider.overrideWith((ref) async => _emptySummary),
        bodyWeightProvider.overrideWith(
          (ref, period) async => _emptyBodyWeight,
        ),
        profileProvider.overrideWith(_StubProfileNotifier.new),
        sessionHistoryProvider.overrideWith(
          (ref) async => const SessionHistoryPage(
            sessions: [],
            total: 0,
            page: 1,
            limit: 20,
          ),
        ),
        // The logger this pushes into opens on the exercise demo, which
        // fetches the catalogue entry. Unstubbed, that demo sits on a
        // spinner the real repository never resolves and pumpAndSettle
        // never returns -- the same reason lastPerformanceProvider is
        // stubbed for the logger elsewhere.
        exerciseDetailProvider.overrideWith(
          (ref, id) async => ExerciseDetail(
            exerciseId: id,
            name: 'Detail $id',
            muscleGroup: 'x',
            equipment: null,
            thumbnailUrl: null,
            animationUrl: null,
            cues: const [],
          ),
        ),
      ],
      child: MaterialApp(theme: fsLightTheme(), home: const TrainingShell()),
    ),
  );
  await tester.pumpAndSettle();
}

class _StubController extends ActiveSessionController {
  _StubController(this.initial);
  final ActiveSession? initial;
  @override
  Future<ActiveSession?> build() async => initial;
}

/// Stands in for the real controller for the Start/Resume entry-point tests
/// below: records every call to [start] and, when [startError] is set,
/// throws it instead of succeeding — the way a deleted plan would surface as
/// an `ApiException` from the server.
class _RecordingController extends ActiveSessionController {
  _RecordingController({this.startError});

  final Object? startError;
  int startCalls = 0;

  @override
  Future<ActiveSession?> build() async => null;

  @override
  Future<void> start({List<int>? exerciseIds}) async {
    startCalls++;
    if (startError != null) throw startError!;
    state = const AsyncValue.data(
      ActiveSession(
        sessionId: 7,
        status: 'in_progress',
        sessionDate: '2026-09-08',
      ),
    );
  }
}

Future<void> _pumpWithController(
  WidgetTester tester,
  ActiveSessionController Function() controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => _plan),
        activeSessionProvider.overrideWith(controller),
        completedDaysProvider.overrideWith((ref) async => const <String>{}),
        // The Progress tab is built eagerly with the rest of the shell. Stubbed
        // at the provider rather than the repository: this file is about the
        // tab bar, and Progress has its own test.
        trainingAnalyticsProvider.overrideWith(
          (ref, period) async => _emptyAnalytics,
        ),
        trainingSummaryProvider.overrideWith((ref) async => _emptySummary),
        bodyWeightProvider.overrideWith(
          (ref, period) async => _emptyBodyWeight,
        ),
        profileProvider.overrideWith(_StubProfileNotifier.new),
        sessionHistoryProvider.overrideWith(
          (ref) async => const SessionHistoryPage(
            sessions: [],
            total: 0,
            page: 1,
            limit: 20,
          ),
        ),
        // The logger this pushes into opens on the exercise demo, which
        // fetches the catalogue entry. Unstubbed, that demo sits on a
        // spinner the real repository never resolves and pumpAndSettle
        // never returns -- the same reason lastPerformanceProvider is
        // stubbed for the logger elsewhere.
        exerciseDetailProvider.overrideWith(
          (ref, id) async => ExerciseDetail(
            exerciseId: id,
            name: 'Detail $id',
            muscleGroup: 'x',
            equipment: null,
            thumbnailUrl: null,
            animationUrl: null,
            cues: const [],
          ),
        ),
        // The logger this pushes into watches this too; without stubbing it,
        // the real repository would reach for a live ApiClient this test
        // never configured.
        lastPerformanceProvider.overrideWith((ref, key) async => const {}),
      ],
      child: MaterialApp(theme: fsLightTheme(), home: const TrainingShell()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows three tabs with Plan selected', (tester) async {
    await _pump(tester);

    expect(find.text('Training'), findsOneWidget);
    expect(find.byKey(const Key('tab.plan')), findsOneWidget);
    expect(find.byKey(const Key('tab.progress')), findsOneWidget);
    expect(find.byKey(const Key('tab.recovery')), findsOneWidget);
    expect(find.text('Week 1 — Full body'), findsOneWidget);
  });

  testWidgets('Progress is a real tab now, and says so honestly when empty', (
    tester,
  ) async {
    // It used to read "once you have logged a few workouts" over a screen
    // that was never wired up, so a user who HAD logged one went looking for
    // a bug in their session instead.
    await _pump(tester);

    await tester.tap(find.byKey(const Key('tab.progress')));
    await tester.pumpAndSettle();
    expect(find.textContaining('once you have logged'), findsNothing);
    // skipOffstage: false -- the Progress tab now leads with four real cards
    // above the history list, so in the test viewport this message sits below
    // the fold. A default finder treats "clipped by the ListView's viewport"
    // the same as "not rendered", which is a fact about this window, not
    // about whether the widget exists -- see nav_shell_test.dart for the same
    // caveat with IndexedStack.
    expect(
      find.byKey(const Key('progress.empty'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('Recovery still says what is coming rather than nothing', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('tab.recovery')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recovery'), findsWidgets);
  });

  testWidgets('the Plan tab offers Start with no session', (tester) async {
    await _pump(tester);
    expect(find.text('Start session'), findsOneWidget);
  });

  testWidgets('the Plan tab offers Resume when one is in progress', (
    tester,
  ) async {
    await _pump(
      tester,
      session: const ActiveSession(
        sessionId: 7,
        status: 'in_progress',
        sessionDate: '2026-09-08',
      ),
    );
    expect(find.text('Resume session'), findsOneWidget);
  });

  // Beyond the brief -- the four tests above only ever check which label the
  // button shows. None of them taps it, so none proves the button actually
  // reaches the controller or opens the logger.
  testWidgets('tapping Start calls start() and pushes the logger', (
    tester,
  ) async {
    final controller = _RecordingController();
    await _pumpWithController(tester, () => controller);

    expect(
      find.byType(SessionLoggerScreen),
      findsNothing,
      reason: 'the logger must not be open before Start is tapped',
    );

    await tester.tap(find.byKey(const Key('session.start')));
    await tester.pumpAndSettle();

    expect(
      controller.startCalls,
      1,
      reason: 'the button must reach the controller, not just relabel itself',
    );
    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  // Beyond the brief -- a failed start (the realistic case: the user's plan
  // was deleted between render and tap, so the server refuses with
  // NO_ACTIVE_PLAN) must show the failure, must not open the logger on top
  // of a session that was never created, and must not strand the user on a
  // Plan tab whose only button is permanently disabled. `_starting` is
  // cleared in a `finally`; if it were not, the second tap below would never
  // reach the controller a second time.
  testWidgets(
    'a failed start shows the message, does not push, and leaves Start usable',
    (tester) async {
      final controller = _RecordingController(
        startError: const ApiException(
          'NO_ACTIVE_PLAN',
          'Your plan was removed.',
        ),
      );
      await _pumpWithController(tester, () => controller);

      await tester.tap(find.byKey(const Key('session.start')));
      await tester.pumpAndSettle();

      expect(find.text('Your plan was removed.'), findsOneWidget);
      expect(find.byType(SessionLoggerScreen), findsNothing);
      expect(controller.startCalls, 1);
      expect(
        find.text('Start session'),
        findsOneWidget,
        reason: 'a failed start must not have left the session as active',
      );

      // Let the SnackBar clear -- it sits at the bottom of the Scaffold over
      // the button and would otherwise swallow the next tap, the same
      // precaution session_logger_screen_test.dart takes before a second
      // Finish tap.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('session.start')));
      await tester.pumpAndSettle();

      expect(
        controller.startCalls,
        2,
        reason:
            'the button must still be wired up after a failed attempt, '
            'not stuck disabled by a _starting flag that was never reset',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the Plan tab offers a way to regenerate', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('plan.regenerate')), findsOneWidget);
    // The icon the start-workout sheet already puts on its AI Workout
    // Generator row: both open the same screen, so they read as one thing.
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    // An icon says nothing on its own, so the tooltip carries the words --
    // it is also what a screen reader announces.
    expect(find.byTooltip('Regenerate plan'), findsOneWidget);
  });

  testWidgets('the other tabs do not offer it', (tester) async {
    await _pump(tester);

    for (final tab in ['progress', 'recovery']) {
      await tester.tap(find.byKey(Key('tab.$tab')));
      await tester.pumpAndSettle();
      // The header is shared by all three tabs, so an action parked there
      // unconditionally would sit above two screens it means nothing on.
      expect(
        find.byKey(const Key('plan.regenerate')),
        findsNothing,
        reason: 'regenerate should not be offered on the $tab tab',
      );
    }
  });

  testWidgets('regenerate opens the generator', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('plan.regenerate')));
    await tester.pumpAndSettle();

    // Straight to the screen that already asks split, days and length, and
    // whose Generate button is the commit -- no confirm in between, since
    // opening it changes nothing.
    expect(find.byType(GeneratorScreen), findsOneWidget);
  });
}
