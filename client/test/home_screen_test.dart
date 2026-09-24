import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/widgets/fs_charts.dart' show FsRing;
import 'package:fitsync/core/widgets/fs_kit.dart' hide FsRing;
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart'
    show exerciseDetailProvider;
import 'package:fitsync/features/home/presentation/home_screen.dart';
import 'package:fitsync/features/home/presentation/widgets/greeting.dart';
import 'package:fitsync/features/home/presentation/widgets/plan_card.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/routine/presentation/routine_screen.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_logger_screen.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart'
    show goalsProvider, streakProvider;
import 'package:fitsync/features/streaks/presentation/streaks_screen.dart';

const _someEquipment = [EquipmentOption(equipmentId: 1, name: 'Dumbbells')];

Profile _profile({
  String fullName = 'Juan Dela Cruz',
  String? mainGoal = 'build_muscle',
  String? fitnessLevel = 'beginner',
  List<EquipmentOption> equipment = _someEquipment,
}) => Profile(
  userId: 1,
  email: 'juan@example.com',
  fullName: fullName,
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: true,
  equipment: equipment,
  injuries: const [],
  mainGoal: mainGoal,
  fitnessLevel: fitnessLevel,
);

const _defaultRecovery = RecoveryOverview(
  todayCheckin: MorningCheckin(
    checkinId: 1,
    checkinDate: '2026-09-24',
    sleepQuality: 'good',
    muscleSoreness: 'none',
    energy: 'moderate',
    stress: 'low',
  ),
  latestEstimate: InjuryRiskEstimate(
    riskLevel: 'low',
    trainingLoadScore: 20,
    checkinDate: '2026-09-24',
  ),
  load: [],
);

const _defaultSummary = TrainingSummary(
  sessionCount: 4,
  setCount: 40,
  totalVolumeKg: 6600,
  newPrCount: 3,
);

final _defaultAnalytics = TrainingAnalytics(
  period: 'month',
  volume: const [
    VolumeBucket(label: 'W1', volumeKg: 1200),
    VolumeBucket(label: 'W2', volumeKg: 1800),
    VolumeBucket(label: 'W3', volumeKg: 1500),
    VolumeBucket(label: 'W4', volumeKg: 2100),
  ],
  change: const VolumeChange(totalKg: 6600, previousKg: 5900, changePct: 12),
  adherence: const Adherence(done: 4, target: 12, weeks: 4),
  muscles: const [],
);

const _defaultRoutine = RoutineDay(
  date: '2026-09-24',
  habits: [
    Habit(
      habitId: 1,
      title: 'Stretch',
      time: '06:30',
      durationMin: 8,
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      done: true,
    ),
    Habit(
      habitId: 2,
      title: 'Read',
      time: '21:00',
      durationMin: null,
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      done: false,
    ),
  ],
  workout: null,
);

const _defaultPlan = WorkoutPlan(
  planId: 1,
  name: 'Upper Body · Push',
  splitStyle: 'upper_lower',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [
    PlanExercise(
      planExerciseId: 301,
      exerciseId: 1,
      name: 'Bench press',
      muscleGroup: 'chest',
      orderNo: 1,
      targetSets: 3,
      targetReps: '8-12',
    ),
  ],
);

/// Answers with one session and records what was abandoned.
class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository([this.session]);

  ActiveSession? session;
  int abandoned = 0;

  @override
  Future<ActiveSession?> active() async => session;

  @override
  Future<void> abandon(int sessionId) async {
    abandoned += 1;
    session = null;
  }

  @override
  Future<Map<int, LastPerformance>> lastPerformance(List<int> ids) async =>
      const {};

  @override
  Future<Set<String>> completedThisWeek() async => const {};

  @override
  String get baseUrl => 'http://test.local';

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// A workout started from the plan: its exercises still come from the plan,
/// so the session carries none of its own.
ActiveSession _planSession({List<LoggedSet> sets = const []}) => ActiveSession(
  sessionId: 7,
  status: 'in_progress',
  sessionDate: '2026-09-14',
  planId: 1,
  planDayNo: 1,
  startedAt: DateTime.now(),
  sets: sets,
);

/// A workout picked by hand: no plan, and it carries its own exercises.
ActiveSession _manualSession({List<LoggedSet> sets = const []}) =>
    ActiveSession(
      sessionId: 8,
      status: 'in_progress',
      sessionDate: '2026-09-14',
      startedAt: DateTime.now(),
      sets: sets,
      exercises: const [
        PlanExercise(
          planExerciseId: 1,
          exerciseId: 101,
          name: 'Goblet squat',
          muscleGroup: 'quadriceps',
          orderNo: 1,
          targetSets: 3,
          targetReps: '8-12',
        ),
        PlanExercise(
          planExerciseId: 2,
          exerciseId: 202,
          name: 'Cable fly',
          muscleGroup: 'pectorals',
          orderNo: 2,
          targetSets: 3,
          targetReps: '8-12',
        ),
      ],
    );

/// A fixed answer instead of a repository round trip — same shape as
/// FakeProfileNotifier in onboarding_flow_test.dart.
class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(this.profile);

  final Profile profile;

  @override
  Future<Profile> build() async => profile;
}

class _StubRoutine extends RoutineController {
  _StubRoutine(this.day, this.error);
  final RoutineDay? day;
  final Object? error;
  @override
  Future<RoutineDay> build() async {
    if (error != null) throw error!;
    return day!;
  }
}

Future<void> _pumpHome(
  WidgetTester tester, {
  VoidCallback? onGoToTrain,
  VoidCallback? onGoToProfile,
  VoidCallback? onGoToProgress,
  VoidCallback? onGoToRecovery,
  Profile? profile,
  WorkoutPlan? plan = _defaultPlan,
  ApiException? planError,
  _FakeSessionRepository? sessions,
  RecoveryOverview? recovery = _defaultRecovery,
  Object? recoveryError,
  TrainingSummary summary = _defaultSummary,
  Object? progressError,
  Object? analyticsError,
  RoutineDay? routine = _defaultRoutine,
  Object? routineError,
  Streak streak = const Streak(
    current: 0,
    best: 0,
    todayActive: false,
    week: [],
  ),
  Object? streakError,
  // Succeeds the first read (the initial load), then throws on every read
  // after that -- a refresh gone wrong, as opposed to streakError's failure
  // from the very start.
  bool streakFailsOnRefresh = false,
}) async {
  var streakReads = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(
          () => _StubProfileNotifier(profile ?? _profile()),
        ),
        activePlanProvider.overrideWith((ref) async {
          if (planError != null) throw planError;
          return plan;
        }),
        sessionRepositoryProvider.overrideWithValue(
          sessions ?? _FakeSessionRepository(),
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
        recoveryOverviewProvider.overrideWith((ref) async {
          if (recoveryError != null) throw recoveryError;
          return recovery!;
        }),
        homeSummaryProvider.overrideWith((ref) async {
          if (progressError != null) throw progressError;
          return summary;
        }),
        trainingAnalyticsProvider.overrideWith((ref, period) async {
          if (analyticsError != null) throw analyticsError;
          return _defaultAnalytics;
        }),
        routineTodayProvider.overrideWith(
          () => _StubRoutine(routine, routineError),
        ),
        streakProvider.overrideWith((ref) async {
          streakReads += 1;
          if (streakError != null ||
              (streakFailsOnRefresh && streakReads > 1)) {
            throw streakError ?? const ApiException('SERVER_ERROR', 'nope');
          }
          return streak;
        }),
        goalsProvider.overrideWith((ref) async => const <LiftGoal>[]),
      ],
      child: MaterialApp(
        home: HomeScreen(
          onGoToTrain: onGoToTrain,
          onGoToProfile: onGoToProfile,
          onGoToProgress: onGoToProgress,
          onGoToRecovery: onGoToRecovery,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a running workout takes the plan card\'s place', (tester) async {
    // Home showed "Today's plan" with a Start button while a workout was
    // already open, so an unfinished session was invisible from the first
    // screen -- and the only hint it existed was the manual picker refusing
    // to start anything.
    await _pumpHome(tester, sessions: _FakeSessionRepository(_planSession()));

    expect(find.byKey(const Key('home.inProgress')), findsOneWidget);
    expect(
      find.byType(PlanCard),
      findsNothing,
      reason: 'the plan card must not offer to start a second workout',
    );
  });

  testWidgets('nothing running leaves the plan card exactly as it was', (
    tester,
  ) async {
    await _pumpHome(tester);

    expect(find.byType(PlanCard), findsOneWidget);
    expect(find.byKey(const Key('home.inProgress')), findsNothing);
  });

  testWidgets('a hand-picked workout is named as one, not as the plan', (
    tester,
  ) async {
    // The whole point: the plan is still there underneath, but what is
    // RUNNING is a one-off the user chose, and Home must say so rather than
    // showing the generated plan's name over it.
    await _pumpHome(tester, sessions: _FakeSessionRepository(_manualSession()));

    expect(
      find.textContaining('Upper Body · Push'),
      findsNothing,
      reason: 'this session did not come from the plan',
    );
    expect(find.textContaining('2 exercises'), findsOneWidget);
  });

  testWidgets('a plan workout is named after the plan', (tester) async {
    await _pumpHome(tester, sessions: _FakeSessionRepository(_planSession()));

    expect(find.textContaining('Upper Body · Push'), findsOneWidget);
  });

  testWidgets('the card says how much has been logged', (tester) async {
    await _pumpHome(
      tester,
      sessions: _FakeSessionRepository(
        _manualSession(
          sets: const [
            LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
            LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 9),
          ],
        ),
      ),
    );

    expect(find.textContaining('2 sets logged'), findsOneWidget);
  });

  testWidgets('a workout with nothing logged yet says so plainly', (
    tester,
  ) async {
    // "0 sets logged" reads like a failure; a just-started workout has simply
    // not been touched yet.
    await _pumpHome(tester, sessions: _FakeSessionRepository(_manualSession()));

    expect(find.textContaining('Not started yet'), findsOneWidget);
    expect(find.textContaining('0 sets'), findsNothing);
  });

  testWidgets('Continue opens the logger', (tester) async {
    await _pumpHome(tester, sessions: _FakeSessionRepository(_planSession()));

    await tester.tap(find.byKey(const Key('home.inProgress.continue')));
    await tester.pumpAndSettle();

    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  testWidgets('discarding asks before throwing the workout away', (
    tester,
  ) async {
    final sessions = _FakeSessionRepository(_planSession());
    await _pumpHome(tester, sessions: sessions);

    await tester.tap(find.byKey(const Key('home.inProgress.discard')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Discard this workout?'), findsOneWidget);
    expect(sessions.abandoned, 0, reason: 'asking is not doing');
  });

  testWidgets('backing out of the question keeps the workout', (tester) async {
    final sessions = _FakeSessionRepository(_planSession());
    await _pumpHome(tester, sessions: sessions);

    await tester.tap(find.byKey(const Key('home.inProgress.discard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(sessions.abandoned, 0);
    expect(find.byKey(const Key('home.inProgress')), findsOneWidget);
  });

  testWidgets('discarding brings today\'s plan back', (tester) async {
    // The plan was never replaced, only covered. Finishing or dropping the
    // workout has to uncover it without a restart.
    final sessions = _FakeSessionRepository(_planSession());
    await _pumpHome(tester, sessions: sessions);

    await tester.tap(find.byKey(const Key('home.inProgress.discard')));
    await tester.pumpAndSettle();
    // The card's own button says "Discard" too, so target the dialog's.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Discard'),
      ),
    );
    await tester.pumpAndSettle();

    expect(sessions.abandoned, 1);
    expect(find.byKey(const Key('home.inProgress')), findsNothing);
    expect(find.byType(PlanCard), findsOneWidget);
  });

  testWidgets('start workout and the nudge each select their tab', (
    tester,
  ) async {
    final selected = <String>[];
    await _pumpHome(
      tester,
      onGoToTrain: () => selected.add('train'),
      onGoToProfile: () => selected.add('profile'),
      profile: _profile(mainGoal: null),
    );

    await tester.tap(find.text('Finish your profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();

    expect(selected, [
      'profile',
      'train',
    ], reason: 'Home selects tabs; it never pushes a second PlanScreen');
  });

  testWidgets('a null plan explains itself and offers no generate action', (
    tester,
  ) async {
    await _pumpHome(tester, plan: null);
    expect(find.text('Start workout'), findsNothing);
    expect(find.textContaining('no active plan'), findsOneWidget);
    expect(
      find.byKey(const Key('home.noPlan')),
      findsOneWidget,
      reason:
          'the descendant check below is vacuous if this key does not '
          'resolve to the no-plan card',
    );
    // Absence of the one specific label is not enough — a relabelled
    // "Generate plan" button would satisfy both assertions above. The
    // no-plan state must offer no action at all, so nothing tappable may
    // exist inside it: there is no on-demand generate endpoint, so a
    // button here would call nothing. Scoped to the home.noPlan-keyed
    // subtree, not the whole screen, so this can't be satisfied or defeated
    // by an unrelated FsButton elsewhere (e.g. a retry button in another
    // state). This key is distinct from PlanScreen's own 'noPlan' key —
    // both tabs build eagerly once visited, and with no active plan both
    // no-plan states can exist in the tree at once, so a shared key would
    // leave any finder using it ambiguous.
    expect(
      find.descendant(
        of: find.byKey(const Key('home.noPlan')),
        matching: find.byType(FsButton),
      ),
      findsNothing,
      reason:
          'the no-plan state must offer no action; a "Generate plan" '
          'button would call an endpoint that does not exist',
    );
  });

  testWidgets('a failed plan load offers a retry', (tester) async {
    await _pumpHome(
      tester,
      planError: const ApiException('X', 'Server is down'),
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'a complete profile leaves no gap where the nudge would have been',
    (tester) async {
      // Both the nudge and its trailing SizedBox(height: 14) live inside the
      // same `if (profileNeedsFinishing(p))` block in home_screen.dart. If
      // that SizedBox ever escaped the conditional (e.g. moved below the
      // closing bracket), the nudge would still correctly disappear for a
      // complete profile, but a 14px gap would remain — invisible to a test
      // that only checks the nudge is absent. Measuring the actual on-screen
      // distance between Greeting and the next section is what catches that:
      // with the nudge suppressed, only the fixed SizedBox(height: 20) after
      // Greeting should separate them.
      //
      // Measured against the readiness card, not the plan card: since Task 7,
      // the readiness section sits unconditionally between the nudge block
      // and the plan card, so the Greeting-to-plan-card distance now
      // legitimately includes its height too and would no longer isolate the
      // nudge's own spacing.
      await _pumpHome(
        tester,
      ); // default profile is complete; default plan renders

      expect(find.text('Finish your profile'), findsNothing);

      final greetingBottom = tester.getBottomLeft(find.byType(Greeting)).dy;
      final readinessTop = tester
          .getTopLeft(find.byKey(const Key('home.readiness')))
          .dy;

      expect(
        readinessTop - greetingBottom,
        moreOrLessEquals(20),
        reason:
            'only the base 20px gap after Greeting should separate it '
            'from the readiness card when the nudge does not render; a '
            'leftover 14px would mean the nudge\'s SizedBox escaped its '
            'conditional',
      );
    },
  );

  testWidgets('the assembled screen does not overflow at 2.0x text scale on a '
      'narrow phone', (tester) async {
    // 320dp mirrors a small phone; 2.0x mirrors Android 14's maximum text
    // scale. Greeting's name text carries no maxLines/Flexible guard of its
    // own — it is safe only because the ListView here leaves it
    // unconstrained the way Greeting's own widget test does. This kit has
    // shipped four text-scale overflow defects already, so the assembled
    // screen gets its own guard rather than trusting each widget's
    // isolated test to cover the composition. mainGoal: null also mounts
    // the nudge, so all three stacked sections are exercised together.
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpHome(tester, profile: _profile(mainGoal: null));

    expect(tester.takeException(), isNull);
  });

  group('readiness and progress', () {
    testWidgets('Home reads top to bottom as the prototype does', (
      tester,
    ) async {
      await _pumpHome(tester);

      double top(Key key) => tester.getTopLeft(find.byKey(key)).dy;
      expect(
        top(const Key('home.readiness')),
        lessThan(tester.getTopLeft(find.byType(PlanCard)).dy),
      );
      expect(
        tester.getTopLeft(find.byType(PlanCard)).dy,
        lessThan(top(const Key('home.progress'))),
      );
    });

    testWidgets('a readiness that fails to load simply is not there', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        recoveryError: const ApiException('INTERNAL', 'x'),
      );
      expect(find.byKey(const Key('home.readiness')), findsNothing);
      expect(find.byType(PlanCard), findsOneWidget);
    });

    testWidgets('progress that fails to load offers a retry', (tester) async {
      await _pumpHome(
        tester,
        progressError: const ApiException('INTERNAL', 'x'),
      );
      expect(find.text("Couldn't load progress"), findsOneWidget);
      expect(find.byKey(const Key('home.progress.retry')), findsOneWidget);
    });

    testWidgets('the analytics half failing alone still shows the same error', (
      tester,
    ) async {
      // Either provider failing is one error line -- half a card would
      // only raise the question of where the other half went.
      await _pumpHome(
        tester,
        analyticsError: const ApiException('INTERNAL', 'x'),
      );
      expect(find.text("Couldn't load progress"), findsOneWidget);
      expect(find.byKey(const Key('home.progress.retry')), findsOneWidget);
    });

    testWidgets('retrying after progress loads successfully shows the card', (
      tester,
    ) async {
      var fail = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(
              () => _StubProfileNotifier(_profile()),
            ),
            activePlanProvider.overrideWith((ref) async => _defaultPlan),
            sessionRepositoryProvider.overrideWithValue(
              _FakeSessionRepository(),
            ),
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
            recoveryOverviewProvider.overrideWith(
              (ref) async => _defaultRecovery,
            ),
            homeSummaryProvider.overrideWith((ref) async {
              if (fail) throw const ApiException('INTERNAL', 'x');
              return _defaultSummary;
            }),
            trainingAnalyticsProvider.overrideWith(
              (ref, period) async => _defaultAnalytics,
            ),
            routineTodayProvider.overrideWith(
              () => _StubRoutine(_defaultRoutine, null),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load progress"), findsOneWidget);

      fail = false;
      await tester.ensureVisible(find.byKey(const Key('home.progress.retry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.progress.retry')));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load progress"), findsNothing);
      expect(find.byKey(const Key('home.progress')), findsOneWidget);
    });

    testWidgets('the cards open Progress and Recovery', (tester) async {
      final taps = <String>[];
      await _pumpHome(
        tester,
        onGoToProgress: () => taps.add('progress'),
        onGoToRecovery: () => taps.add('recovery'),
      );

      // The ring, not the card's centre: the centre can land on the chip.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('home.readiness')),
          matching: find.byType(FsRing),
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('home.progress')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.progress')));

      expect(taps, ['recovery', 'progress']);
    });

    testWidgets('the check-in chip opens the check-in sheet', (tester) async {
      await _pumpHome(tester);
      await tester.tap(find.byKey(const Key('home.readiness.checkin')));
      await tester.pumpAndSettle();
      expect(find.text('Morning check-in'), findsOneWidget);
    });
  });

  group('routine', () {
    testWidgets('the routine card sits below the progress card', (
      tester,
    ) async {
      await _pumpHome(tester);
      // scrollUntilVisible, not ensureVisible: this is a ListView, which does
      // not build what it has not reached, and the routine card sits below
      // the progress card, out of the test viewport's initial build range.
      await tester.scrollUntilVisible(
        find.byKey(const Key('home.routine')),
        200,
      );
      await tester.pumpAndSettle();

      final progressTop = tester
          .getTopLeft(find.byKey(const Key('home.progress')))
          .dy;
      final routineTop = tester
          .getTopLeft(find.byKey(const Key('home.routine')))
          .dy;

      expect(progressTop, lessThan(routineTop));
    });

    testWidgets('a routine that fails to load offers a retry', (tester) async {
      await _pumpHome(
        tester,
        routineError: const ApiException('INTERNAL', 'x'),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('home.routine.retry')),
        200,
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load your routine"), findsOneWidget);
      expect(find.byKey(const Key('home.routine.retry')), findsOneWidget);
    });

    testWidgets('tapping the card opens the routine screen', (tester) async {
      await _pumpHome(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('home.routine')),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.routine')));
      await tester.pumpAndSettle();

      expect(find.byType(RoutineScreen), findsOneWidget);
      // The screen reads routineTodayProvider itself, so it shows the same
      // stubbed day Home's own card summarised.
      expect(find.text('Stretch'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
    });

    testWidgets('the routine card carries the streak and opens it', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        streak: const Streak(
          current: 12,
          best: 18,
          todayActive: true,
          week: [],
        ),
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('home.routine.streak')),
        200,
      );
      await tester.pumpAndSettle();
      expect(find.text('12-day streak'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home.routine.streak')));
      await tester.pumpAndSettle();

      expect(find.byType(StreaksScreen), findsOneWidget);
    });

    testWidgets('a streak that fails to load leaves no tag', (tester) async {
      await _pumpHome(
        tester,
        streakError: const ApiException('SERVER_ERROR', 'nope'),
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('home.routine')),
        200,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home.routine.streak')), findsNothing);
    });

    testWidgets('a streak that fails to refresh drops its tag', (tester) async {
      await _pumpHome(
        tester,
        streak: const Streak(
          current: 12,
          best: 18,
          todayActive: true,
          week: [],
        ),
        streakFailsOnRefresh: true,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('home.routine.streak')),
        200,
      );
      await tester.pumpAndSettle();
      expect(find.text('12-day streak'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      container.invalidate(streakProvider);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home.routine.streak')), findsNothing);
    });

    testWidgets(
      'tapping the workout row from the routine screen returns to Home and '
      'opens Train',
      (tester) async {
        var wentToTrain = false;
        const dayWithWorkout = RoutineDay(
          date: '2026-09-24',
          habits: [],
          workout: RoutineWorkout(title: 'Upper Body', done: false),
        );
        await _pumpHome(
          tester,
          onGoToTrain: () => wentToTrain = true,
          routine: dayWithWorkout,
        );

        await tester.scrollUntilVisible(
          find.byKey(const Key('home.routine')),
          200,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('home.routine')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('routine.workout')));
        await tester.pumpAndSettle();

        expect(wentToTrain, isTrue);
        expect(find.byType(RoutineScreen), findsNothing);
      },
    );
  });
}
