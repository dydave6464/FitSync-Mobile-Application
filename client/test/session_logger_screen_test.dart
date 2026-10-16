import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_cues.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart'
    show exerciseDetailProvider, exerciseCuesProvider;
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/exercise_alternative.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/plans/presentation/exercise_swap_sheet.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/sessions/data/rest_alerts.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_logger_screen.dart';
import 'package:fitsync/features/sessions/presentation/widgets/rest_timer.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_row.dart';

import 'helpers/fake_rest_alerts.dart';
import 'helpers/fake_training_settings.dart';

/// Records haptic calls, which go to the platform channel.
List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method.startsWith('HapticFeedback')) calls.add(call.method);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

/// The order a phone reports going away: locked, or the app switched.
Future<void> _background(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

Future<void> _foreground(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

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
    PlanExercise(
      planExerciseId: 602,
      exerciseId: 102,
      name: 'Push-up',
      muscleGroup: 'chest',
      orderNo: 2,
      targetSets: 2,
      targetReps: '10-15',
    ),
  ],
);

/// Same two exercises as [_plan], split across two rotation days -- for the
/// one test that needs the logger to filter rather than show everything.
/// Kept separate from [_plan] rather than folding the day split into it:
/// every other test in this file pumps [_plan] through a session with no
/// planDayNo, and a filtered logger can only ever show one day at a time --
/// splitting the shared fixture would silently drop Push-up out of every one
/// of those, since none of them would resolve to day 2.
const _rotationPlan = WorkoutPlan(
  planId: 42,
  name: 'Week 1 — Full body',
  splitStyle: 'push_pull_legs',
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
      dayNo: 1,
    ),
    PlanExercise(
      planExerciseId: 602,
      exerciseId: 102,
      name: 'Push-up',
      muscleGroup: 'chest',
      orderNo: 2,
      targetSets: 2,
      targetReps: '10-15',
      dayNo: 2,
    ),
  ],
);

/// Stands in for the real controller so the screen can be driven without a
/// network. Records what the screen asked for.
class FakeSessionController extends ActiveSessionController {
  FakeSessionController(this.initial);

  final ActiveSession? initial;
  final List<String> calls = [];
  Object? logSetError;
  Object? unlogSetError;
  Object? completeError;
  Object? abandonError;

  /// When set, [abandon] suspends here after recording the call -- a discard
  /// still in flight when the phone is locked. Null resolves immediately.
  Completer<void>? abandonGate;

  /// When set, [complete] suspends here before doing anything else -- lets a
  /// test dispatch a second Finish tap while the first is still in flight,
  /// the way two rapid taps would race a real network round trip. Null (the
  /// default) resolves immediately, matching every test that isn't exercising
  /// that race.
  Completer<void>? completeGate;

  /// When set, [logSet] suspends here after recording the call -- a set
  /// still saving when the phone is locked. Null resolves immediately.
  Completer<void>? logSetGate;

  @override
  Future<ActiveSession?> build() async => initial;

  @override
  Future<void> logSet({
    required int exerciseId,
    required int setNumber,
    double? weightKg,
    int? reps,
  }) async {
    calls.add('log:$exerciseId:$setNumber:$weightKg:$reps');
    if (logSetGate != null) await logSetGate!.future;
    if (logSetError != null) throw logSetError!;
    state = AsyncValue.data(
      state.value!.withSet(
        LoggedSet(
          exerciseId: exerciseId,
          setNumber: setNumber,
          weightKg: weightKg,
          reps: reps,
        ),
      ),
    );
  }

  @override
  Future<void> unlogSet({
    required int exerciseId,
    required int setNumber,
  }) async {
    calls.add('unlog:$exerciseId:$setNumber');
    if (unlogSetError != null) throw unlogSetError!;
    state = AsyncValue.data(state.value!.withoutSet(exerciseId, setNumber));
  }

  @override
  Future<ActiveSession> complete(int durationMin) async {
    // Recorded on entry, before any gate or guard. `calls` is the record of
    // what the SCREEN asked for; recording it after the in-progress check
    // below would hide a second call that the controller rejected, and
    // hiding it is exactly what the two-taps test exists to catch.
    calls.add('complete:$durationMin');
    if (completeGate != null) await completeGate!.future;
    // Mirrors the real controller's _current contract: completing a session
    // that is already closed (by an earlier call) must not proceed silently.
    if (state.value == null) {
      throw StateError('No session is in progress.');
    }
    if (completeError != null) throw completeError!;
    // sessionId and planId carried over from the session being closed, not
    // hardcoded: the offer-to-keep tests finish sessions with their own
    // sessionId and check what reached the plan API, and a plan-backed
    // session's summary must still read as plan-backed.
    final source = state.value!;
    final done = ActiveSession(
      sessionId: source.sessionId,
      status: 'completed',
      sessionDate: '2026-09-08',
      planId: source.planId,
      durationMin: durationMin,
      totalVolumeKg: 380,
      sets: source.sets,
    );
    state = const AsyncValue.data(null);
    return done;
  }

  @override
  Future<void> abandon() async {
    calls.add('abandon');
    if (abandonGate != null) await abandonGate!.future;
    if (abandonError != null) throw abandonError!;
    state = const AsyncValue.data(null);
  }

  /// The session the controller is still holding, for tests that assert a
  /// failed write left it in progress. Exposed as a getter because `state` is
  /// protected: reading it from the test body directly would be an
  /// invalid_use_of_protected_member analyzer failure.
  ActiveSession? get heldSession => state.value;
}

class FakeProfileNotifier extends ProfileNotifier {
  FakeProfileNotifier(this.unit, this.patches);

  final WeightUnit unit;
  final List<Map<String, dynamic>> patches;

  @override
  Future<Profile> build() async => Profile(
    userId: 7,
    email: 'j@example.com',
    fullName: 'J',
    onboardingCompleted: true,
    isPremium: false,
    notificationsEnabled: true,
    equipment: const [],
    injuries: const [],
    weightUnit: unit,
  );

  @override
  Future<void> patch(Map<String, dynamic> fields) async => patches.add(fields);
}

/// The plan the generator built: what "Add to my plan" would silently throw
/// away, and what the confirmation has to name.
const _generatedPlan = WorkoutPlan(
  planId: 42,
  name: 'Week 1 — Full body',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  source: 'generated',
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

/// A plan the user already built. Adding to this replaces nothing.
const _customPlan = WorkoutPlan(
  planId: 9,
  name: 'My Full Body',
  splitStyle: 'full_body',
  daysPerWeek: 1,
  sessionLengthMin: 45,
  weekNo: 1,
  source: 'custom',
  exercises: [
    PlanExercise(
      planExerciseId: 1,
      exerciseId: 101,
      name: 'Bench press',
      muscleGroup: 'chest',
      orderNo: 1,
      targetSets: 3,
      targetReps: '8-12',
      dayNo: 1,
    ),
  ],
);

/// Records what the summary dialog asked the plan API to do.
class RecordingPlanRepository implements PlanRepository {
  RecordingPlanRepository({
    this.error,
    this.active,
    this.gate,
    this.swapped,
    this.swapGate,
    this.refetchGate,
    this.refetchError,
    this.alternativeRows = const [],
  });

  final Object? error;

  /// What `activePlan` answers -- until a [swap] lands, when it becomes
  /// [swapped], as the server's plan would.
  WorkoutPlan? active;

  /// The plan after a swap, for the tests that switch an exercise.
  final WorkoutPlan? swapped;

  /// What the swap sheet lists, whatever row or search asks.
  final List<ExerciseAlternative> alternativeRows;

  /// Every swap asked for, as (planExerciseId, exerciseId).
  final List<(int, int)> swaps = [];

  /// When set, `swap` holds here before it lands, so a test can dismiss the
  /// sheet while the server is still answering.
  final Completer<void>? swapGate;

  /// When set, every `activePlan` after a swap holds here until it completes,
  /// so a test can look at the logger between the sheet closing and the new
  /// plan landing.
  final Completer<void>? refetchGate;

  /// When set, every `activePlan` after a swap fails with this, as a refetch
  /// that never reaches the server would.
  final Object? refetchError;

  /// When set, `planFromSession` suspends here instead of resolving
  /// immediately -- mirrors [FakeSessionController.completeGate], and for the
  /// same kind of test: it lets a real network round trip outlive the
  /// summary route, which pops synchronously on tap while this is still in
  /// flight.
  final Completer<WorkoutPlan>? gate;

  int fromSessionCalls = 0;
  int? lastSessionId;
  int? lastDayNo;
  String? lastSplitStyle;

  @override
  Future<WorkoutPlan?> activePlan() async {
    if (swaps.isNotEmpty) {
      await refetchGate?.future;
      if (refetchError != null) throw refetchError!;
    }
    return active;
  }

  @override
  Future<List<ExerciseAlternative>> alternatives(
    int planExerciseId, {
    String? q,
  }) async => alternativeRows;

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async {
    swaps.add((planExerciseId, exerciseId));
    await swapGate?.future;
    active = swapped;
    return swapped!;
  }

  @override
  Future<WorkoutPlan> planFromSession({
    required int sessionId,
    String? splitStyle,
    int? dayNo,
  }) async {
    fromSessionCalls += 1;
    lastSessionId = sessionId;
    lastDayNo = dayNo;
    lastSplitStyle = splitStyle;
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    return const WorkoutPlan(
      planId: 9,
      name: 'My Full Body',
      splitStyle: 'full_body',
      daysPerWeek: 1,
      sessionLengthMin: 45,
      weekNo: 1,
      exercises: [],
      source: 'custom',
    );
  }

  @override
  String get baseUrl => 'http://test.local';

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

ActiveSession _session({
  int sessionId = 7,
  int? planId,
  List<LoggedSet> sets = const [],
  int? planDayNo,
  List<PlanExercise> exercises = const [],
}) => ActiveSession(
  sessionId: sessionId,
  status: 'in_progress',
  sessionDate: '2026-09-08',
  startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
  planId: planId,
  sets: sets,
  planDayNo: planDayNo,
  exercises: exercises,
);

/// A session started from a chosen list: no plan, no rotation day, and its
/// exercises carried on the session itself.
final _manualSession = _session(
  exercises: const [
    PlanExercise(
      planExerciseId: 5,
      exerciseId: 301,
      name: 'Cable fly',
      muscleGroup: 'pectorals',
      orderNo: 1,
      targetSets: 3,
      targetReps: '10-12',
    ),
  ],
);

/// Same shape as [_manualSession], with a set already logged and its own
/// sessionId -- what the offer-to-keep tests finish, since unlike every
/// other test in this file they need to assert on which sessionId reached
/// the plan API.
ActiveSession _manualSessionWithSets() => _session(
  sessionId: 9,
  exercises: const [
    PlanExercise(
      planExerciseId: 5,
      exerciseId: 301,
      name: 'Cable fly',
      muscleGroup: 'pectorals',
      orderNo: 1,
      targetSets: 3,
      targetReps: '10-12',
    ),
  ],
  sets: const [
    LoggedSet(exerciseId: 301, setNumber: 1, weightKg: 20, reps: 10),
  ],
);

/// A plan-backed session with a set already logged -- already part of a
/// plan, so the offer to keep it must not appear for this one.
ActiveSession _planSessionWithSets() => _session(
  sessionId: 9,
  planId: 42,
  sets: const [
    LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
  ],
);

/// Pushes the logger the way the Training shell does, rather than mounting it
/// as `home`. The screen pops itself on finish, on discard and when the
/// session turns out to be closed already; as a root route those pops would
/// empty the navigator, taking the Scaffold -- and with it any SnackBar --
/// down with it, so a root-mounted logger could never show that a pop had
/// happened or that a message had landed. Pushing over a host route reproduces
/// the real stack: the pop returns here, and the host's Scaffold is what the
/// ScaffoldMessenger hands the SnackBar to.
Future<FakeSessionController> _pump(
  WidgetTester tester, {
  ActiveSession? session,
  WeightUnit unit = WeightUnit.kg,
  List<Map<String, dynamic>>? patches,
  WorkoutPlan? plan = _plan,
  PlanRepository? plans,
  // What /sessions/last-performance answers, keyed by exercise. Supplied
  // through an async override, as the real provider is -- so the logger's
  // first frame renders before it lands, exactly as it does on a phone.
  Map<int, LastPerformance> last = const {},
  ExerciseCues? cues,
  // Holds /sessions/last-performance open instead of answering [last]
  // immediately. The set table is a tap away from the pump now, so a prefill
  // supplied through [last] has always landed by the time the table is first
  // drawn -- which is precisely the frame the prefill used to be lost in.
  // Gating it is what puts that frame back.
  Completer<Map<int, LastPerformance>>? lastGate,
  // What /exercises/:id answers for the demo stage. Null takes the resolving
  // stub below; a test drives the stage's loading and error branches by
  // handing over a future that never completes, or one that fails.
  Future<ExerciseDetail> Function(int id)? detail,
  // False runs the push with explicit frames instead of pumpAndSettle. A demo
  // still in flight shows a spinner, and a spinner schedules frames forever,
  // so settling would time out rather than return.
  bool settle = true,
  // Called every time the override actually recomputes -- i.e. the provider
  // was freshly built or freshly invalidated, not served from cache. Only
  // the disposed-State invalidation test below reads it; every other test
  // leaves it null.
  VoidCallback? onActivePlanRead,
  // The saved rest between sets. Every test gets the store, since the logger
  // reads it on its first frame; a test that cares passes its own.
  FakeTrainingSettings? training,
  // The phone's notifications for the rest alert. Every test gets a fake --
  // granted, so the first rest asks nothing -- and an in-memory store, so no
  // test touches a platform channel.
  FakeRestAlertScheduler? alerts,
  RestAlertStore? alertStore,
}) async {
  final controller = FakeSessionController(session ?? _session());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The rest reads time from here; the binding's fake clock advances
        // with every pump, so a test can run a rest down by pumping.
        restNowProvider.overrideWithValue(() => tester.binding.clock.now()),
        activePlanProvider.overrideWith((ref) async {
          onActivePlanRead?.call();
          // Routed through the fake repository when one is supplied, mirroring
          // the real provider (activePlanProvider just reads
          // planRepositoryProvider.activePlan()) -- so a RecordingPlanRepository
          // with its own `active` drives this the same way the server would,
          // without a second, disconnected knob to keep in sync. Every test
          // that only cares about the exercises on screen never sets `active`
          // and keeps using `plan` as before.
          if (plans != null) return plans.activePlan();
          return plan;
        }),
        profileProvider.overrideWith(
          () => FakeProfileNotifier(unit, patches ?? []),
        ),
        activeSessionProvider.overrideWith(() => controller),
        lastPerformanceProvider.overrideWith(
          (ref, key) async => lastGate != null ? lastGate.future : last,
        ),
        if (plans != null) planRepositoryProvider.overrideWithValue(plans),
        trainingSettingsRepositoryProvider.overrideWithValue(
          training ?? FakeTrainingSettings(),
        ),
        restAlertSchedulerProvider.overrideWithValue(
          alerts ?? FakeRestAlertScheduler(),
        ),
        restAlertStoreProvider.overrideWithValue(
          alertStore ?? RestAlertStore(backing: InMemorySecureStore()),
        ),
        // Live for every test in this file: the demo stage reads this too, and
        // an unstubbed fetch would hang pumpAndSettle. `cues` lets one test
        // supply an AI answer; the rest get the catalogue default.
        exerciseCuesProvider.overrideWith(
          (ref, id) async =>
              cues ??
              const ExerciseCues(
                source: 'catalogue',
                injuryName: null,
                cues: [],
              ),
        ),
        // Live for every test in this file, not just the pushed-screen one:
        // each exercise opens on a demo stage that reads this.
        exerciseDetailProvider.overrideWith(
          (ref, id) => detail != null
              ? detail(id)
              : Future.value(
                  ExerciseDetail(
                    exerciseId: id,
                    name: 'Detail $id',
                    muscleGroup: 'x',
                    equipment: null,
                    thumbnailUrl: null,
                    animationUrl: null,
                    cues: const [],
                  ),
                ),
        ),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SessionLoggerScreen(),
                ),
              ),
              child: const Text('open logger'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open logger'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  return controller;
}

const _repsPrefill = {
  101: LastPerformance(exerciseId: 101, reps: 10, sessionDate: '2026-09-12'),
  102: LastPerformance(exerciseId: 102, reps: 12, sessionDate: '2026-09-12'),
};

/// Pumps the logger and advances past the demo stage to the set table, which
/// is where most of these tests do their work.
///
/// Every exercise opens on its demo now, so a test that asserts on the table
/// -- its fields, its rows, its unit toggle, or the footer's logging labels --
/// has to walk the one tap a user walks to get there. What those tests assert
/// is unchanged; only the way they reach the table is.
///
/// [last] defaults to last session's reps for both of [_plan]'s exercises, as
/// anyone who has trained before sees. A set with an empty reps box asks
/// before logging, and these tests are about what logging a set does, not
/// that question -- logger_action_test.dart covers it. No weight is
/// prefilled, so what these tests send as weight is unchanged. A test about
/// fields being emptied passes `const {}`, or the prefill would refill them.
Future<FakeSessionController> _pumpLogging(
  WidgetTester tester, {
  ActiveSession? session,
  WeightUnit unit = WeightUnit.kg,
  List<Map<String, dynamic>>? patches,
  WorkoutPlan? plan = _plan,
  FakeTrainingSettings? training,
  FakeRestAlertScheduler? alerts,
  RestAlertStore? alertStore,
  Map<int, LastPerformance> last = _repsPrefill,
}) async {
  final controller = await _pump(
    tester,
    session: session,
    unit: unit,
    patches: patches,
    plan: plan,
    training: training,
    alerts: alerts,
    alertStore: alertStore,
    last: last,
  );
  await tester.tap(find.byKey(const Key('logger.primary')));
  await tester.pumpAndSettle();
  return controller;
}

/// The meta row's position counter.
///
/// The demo stage carries a counter of its own and now spells it the same
/// way (`Exercise 2 / 2`, matching the meta row rather than "2 of 2"), so a
/// bare textContaining matches twice whenever the demo is the stage on
/// screen. These assertions are about the header, so they say so.
Finder _metaPosition(String text) => find.descendant(
  of: find.byKey(const Key('logger.position')),
  matching: find.textContaining(text),
);

/// Finish and Discard moved into the app bar's overflow menu, so reaching
/// either takes the two taps a user makes rather than one. The menu route's
/// dismissal is what carries the selection to onSelected, so this settles
/// before returning -- a bare tap on the item would leave the action pending.
Future<void> _menu(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(const Key('logger.menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('logger.$action')));
  await tester.pumpAndSettle();
}

void main() {
  // The mockup's screen 3. It is a stage of this screen, not a route, so the
  // session and the rest timer survive moving between the two.
  testWidgets('an exercise opens on its demo before its set table', (
    tester,
  ) async {
    await _pump(tester, session: _manualSession, plan: null);

    expect(find.byKey(const Key('logger.demo')), findsOneWidget);
    expect(find.byType(SetRow), findsNothing);
    expect(find.text('Start logging'), findsOneWidget);
  });

  // The payoff of the whole injury gate, seen from the screen: cues written
  // for the user's own reported injury, named as such.
  testWidgets('the demo stage shows cues written for a reported injury', (
    tester,
  ) async {
    await _pump(
      tester,
      session: _manualSession,
      plan: null,
      cues: const ExerciseCues(
        source: 'ai',
        injuryName: 'Shoulder',
        cues: [
          Cue(title: 'Pull to the navel', detail: 'Keeps it out of the arc.'),
        ],
      ),
    );

    expect(find.byKey(const Key('logger.demo')), findsOneWidget);
    expect(find.text('AI coaching cues'), findsOneWidget);
    expect(find.text('Shoulder'), findsOneWidget);
    expect(find.text('Pull to the navel'), findsOneWidget);
  });

  // The other half, and the reason the gate exists: an exercise that loads
  // nothing injured costs nothing and says nothing about AI.
  testWidgets('an unflagged exercise shows plain catalogue cues', (
    tester,
  ) async {
    await _pump(
      tester,
      session: _manualSession,
      plan: null,
      cues: const ExerciseCues(
        source: 'catalogue',
        injuryName: null,
        cues: [Cue(title: 'Brace before you press.')],
      ),
    );

    expect(find.text('How to perform'), findsOneWidget);
    expect(find.text('AI coaching cues'), findsNothing);
    expect(find.text('Brace before you press.'), findsOneWidget);
  });

  testWidgets('Start logging reveals the set table', (tester) async {
    await _pump(tester, session: _manualSession, plan: null);

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('logger.demo')), findsNothing);
    expect(find.byType(SetRow), findsWidgets);
  });

  // The set table's tile plays the animation the demo stage already fetched
  // (exerciseDetailProvider), joined to the same base URL, so it is the
  // cached image rather than a second download.
  testWidgets('the set table tile plays the exercise animation', (
    tester,
  ) async {
    await _pump(
      tester,
      session: _manualSession,
      plan: null,
      detail: (id) => Future.value(
        ExerciseDetail(
          exerciseId: id,
          name: 'Cable fly',
          muscleGroup: 'pectorals',
          equipment: null,
          thumbnailUrl: null,
          animationUrl: '/storage/exercises/$id/anim.gif',
          cues: const [],
        ),
      ),
    );
    // The URL the demo stage loads -- the one the image cache now holds.
    final demoUrls = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<NetworkImage>()
        .map((n) => n.url)
        .where((u) => u.endsWith('/storage/exercises/301/anim.gif'))
        .toList();
    expect(demoUrls, hasLength(1));

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    final animation = find.byKey(const ValueKey('thumb.animation'));
    expect(animation, findsOneWidget);
    expect(
      (tester.widget<Image>(animation).image as NetworkImage).url,
      demoUrls.single,
    );
  });

  testWidgets('no rest tag before a set is logged', (tester) async {
    await _pump(tester, session: _manualSession, plan: null);

    expect(find.byType(RestTimer), findsNothing);
  });

  // A rest is the user's, between their sets, whichever exercise is on
  // screen: walking from the squat rack to the bench is part of it.
  testWidgets('a rest started on the table keeps counting on the demo', (
    tester,
  ) async {
    await _pumpLogging(tester, session: _manualSession, plan: null);

    await tester.enterText(find.byKey(const Key('set.1.weight')), '20');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '10');
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    await tester.tap(find.byKey(const Key('logger.back')));
    await tester.pump();

    expect(find.byKey(const Key('logger.demo')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
      '1:20',
    );
  });

  // The rest after the last set of an exercise is the one most worth keeping:
  // it is the walk to the next one.
  testWidgets('the rest after the last set carries into the next exercise', (
    tester,
  ) async {
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
        ],
      ),
    );

    await tester.enterText(find.byKey(const Key('set.3.weight')), '20');
    await tester.enterText(find.byKey(const Key('set.3.reps')), '10');
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    // Next exercise (its demo), then its table.
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(RestTimer), findsOneWidget);
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SetRow), findsWidgets);
    // The same rest, 5 seconds down -- not a fresh 90.
    expect(
      tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
      '1:25',
    );
  });

  testWidgets('stepping back and forth keeps the same rest, not a fresh one', (
    tester,
  ) async {
    await _pumpLogging(tester, session: _manualSession, plan: null);

    await tester.enterText(find.byKey(const Key('set.1.weight')), '20');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '10');
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    await tester.tap(find.byKey(const Key('logger.back')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SetRow), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
      '1:20',
    );
  });

  testWidgets("a rest follows a jump onto another exercise's table", (
    tester,
  ) async {
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
          // Push-up already has a set, so the jump lands on its table.
          LoggedSet(exerciseId: 102, setNumber: 1, weightKg: 0, reps: 12),
        ],
      ),
    );

    await tester.enterText(find.byKey(const Key('set.3.weight')), '20');
    await tester.enterText(find.byKey(const Key('set.3.reps')), '10');
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('logger.position')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('jump.102')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SetRow), findsWidgets);
    expect(find.byType(RestTimer), findsOneWidget);
  });

  testWidgets('back from the set table returns to the demo', (tester) async {
    await _pump(tester, session: _manualSession, plan: null);

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();
    expect(find.byType(SetRow), findsWidgets);

    await tester.tap(find.byKey(const Key('logger.back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('logger.demo')), findsOneWidget);
  });

  // The stage's error branch carries a deliberate promise -- a demo that will
  // not load must never be what stops someone logging their sets -- and
  // nothing asserted either half of it. Every other test here stubs a detail
  // that resolves.
  testWidgets('a demo that will not load does not block the workout', (
    tester,
  ) async {
    await _pump(
      tester,
      session: _manualSession,
      plan: null,
      detail: (_) => Future<ExerciseDetail>.error(
        const ApiException('EXERCISE_NOT_FOUND', 'No such exercise.'),
      ),
    );

    expect(
      find.text('Could not load this exercise. You can still log your sets.'),
      findsOneWidget,
    );
    // Present is not enough: the way on has to still work.
    expect(find.byKey(const Key('logger.primary')), findsOneWidget);

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(find.byType(SetRow), findsWidgets);
  });

  testWidgets('a demo still loading shows a spinner, not a blank stage', (
    tester,
  ) async {
    // Never completed, so the fetch is in flight for the whole test.
    final gate = Completer<ExerciseDetail>();
    await _pump(
      tester,
      session: _manualSession,
      plan: null,
      detail: (_) => gate.future,
      settle: false,
    );

    expect(find.byKey(const Key('logger.demo')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a session with no plan renders the exercises it carries', (
    tester,
  ) async {
    // A manual session has no plan at all. The screen used to require one and
    // showed a bare spinner otherwise -- no AppBar, no way back, after
    // POST /sessions had already opened the session.
    await _pumpLogging(tester, session: _manualSession, plan: null);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Cable fly'), findsOneWidget);
  });

  // The repeat-last-workout complaint, end to end. The shortcut loads the
  // exercises but not the numbers, so the fields are the only place last
  // week's kg and reps can come from -- and they are fetched, which means the
  // table is already built and keyed by the time they arrive. Asserted through
  // the screen rather than the panel because the async gap is the bug: a panel
  // handed its prefill up front never reproduces it.
  testWidgets(
    'the last session\'s kg and reps reach the fields once they load',
    (tester) async {
      final gate = Completer<Map<int, LastPerformance>>();
      await _pump(tester, session: _manualSession, plan: null, lastGate: gate);
      // On the table before the prefill exists -- the exercise opens on its
      // demo now, so reaching the table is a tap rather than a pump.
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();

      gate.complete(const {
        301: LastPerformance(
          exerciseId: 301,
          weightKg: 32.5,
          reps: 12,
          sessionDate: '2026-09-12',
        ),
      });
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('set.1.weight')))
            .controller!
            .text,
        '32.5',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('set.1.reps')))
            .controller!
            .text,
        '12',
      );
    },
  );

  testWidgets('a session with no plan says so rather than naming nothing', (
    tester,
  ) async {
    // The header reads "Exercise 1 / 3 · <plan name>". With no plan that
    // trails off after the separator, which looks like a rendering fault.
    await _pumpLogging(tester, session: _manualSession, plan: null);

    expect(find.textContaining('Manual workout'), findsOneWidget);
  });

  testWidgets('a session carrying exercises prefers them over the plan', (
    tester,
  ) async {
    // Belt and braces: a manual session must not fall through to whatever
    // plan the user happens to have and log against someone else's day.
    await _pumpLogging(tester, session: _manualSession, plan: _plan);

    expect(find.text('Cable fly'), findsOneWidget);
    expect(find.text('Goblet squat'), findsNothing);
  });

  testWidgets('shows one exercise at a time, not the whole plan', (
    tester,
  ) async {
    await _pumpLogging(tester);

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Push-up'), findsNothing);
  });

  testWidgets('the footer advances to the next exercise', (tester) async {
    // The footer now logs the active set; pre-loading every set on the
    // first exercise is what makes it read "Next exercise" instead.
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 3, weightKg: 20, reps: 10),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();
    // Next exercise lands on exercise 2's demo; its panel -- the only place
    // the plan's own name for it is written -- is one Start logging away.
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(find.text('Push-up'), findsOneWidget);
    expect(find.text('Goblet squat'), findsNothing);
  });

  testWidgets('the header names the position in the workout', (tester) async {
    // The footer now logs the active set; pre-loading every set on the
    // first exercise is what makes it read "Next exercise" instead.
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 3, weightKg: 20, reps: 10),
        ],
      ),
    );
    expect(_metaPosition('Exercise 1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(_metaPosition('Exercise 2 / 2'), findsOneWidget);
  });

  testWidgets(
    'the position counter opens a sheet listing every exercise with its progress',
    (tester) async {
      await _pump(
        tester,
        session: _session(
          sets: const [
            LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('logger.position')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('jump.101')), findsOneWidget);
      expect(find.byKey(const Key('jump.102')), findsOneWidget);
      // Counted per exercise against its own target, not session-wide: the
      // squat has one of its three, the push-up none of its two. Scoped to the
      // row, because the panel behind the sheet carries the same text for
      // whichever exercise is on screen.
      expect(
        find.descendant(
          of: find.byKey(const Key('jump.101')),
          matching: find.text('1/3 sets'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('jump.102')),
          matching: find.text('0/2 sets'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('choosing an exercise from the sheet goes straight to it', (
    tester,
  ) async {
    await _pumpLogging(tester);

    await tester.tap(find.byKey(const Key('logger.position')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('jump.102')));
    await tester.pumpAndSettle();
    // Nothing is logged against Push-up, so the jump lands on its demo; the
    // panel -- the only place the plan's own name for it is written -- is one
    // Start logging away.
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    // Both, deliberately: the counter alone would pass if the sheet moved the
    // index without the body following, and the name alone would pass if the
    // body moved without the header.
    expect(_metaPosition('Exercise 2 / 2'), findsOneWidget);
    expect(find.text('Push-up'), findsOneWidget);
  });

  // The jump sheet is navigation, so it decides a stage rather than
  // inheriting one. Started from exercise 1's TABLE on purpose: a jump that
  // simply kept the stage it was on would land on a table here and pass a
  // weaker test.
  testWidgets('jumping to an exercise with nothing logged opens its demo', (
    tester,
  ) async {
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('logger.position')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('jump.102')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('logger.demo')), findsOneWidget);
    expect(find.byType(SetRow), findsNothing);
  });

  // And the other direction, from exercise 1's DEMO, for the same reason. A
  // set already logged against the target means the user was prepared for it
  // once already -- going back to fix a number must not make them walk past
  // cues they have read, the same judgement the back handler makes.
  testWidgets('jumping to an exercise already logged against opens its table', (
    tester,
  ) async {
    await _pump(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 102, setNumber: 1, weightKg: 20, reps: 10),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('logger.position')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('jump.102')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('logger.demo')), findsNothing);
    expect(find.text('Push-up'), findsOneWidget);
  });

  testWidgets('back steps to the previous exercise before leaving the logger', (
    tester,
  ) async {
    // The footer now logs the active set; pre-loading every set on the
    // first exercise is what makes it read "Next exercise" instead.
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 3, weightKg: 20, reps: 10),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();
    expect(_metaPosition('Exercise 2 / 2'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(_metaPosition('Exercise 1 / 2'), findsOneWidget);
    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  // The other half of the PopScope: blocking the pop unconditionally would
  // trap someone on the first exercise with no way out but Finish or Discard.
  testWidgets('back from the first exercise leaves the logger', (tester) async {
    await _pump(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SessionLoggerScreen), findsNothing);
    expect(find.text('open logger'), findsOneWidget);
  });

  testWidgets('the summary reports the volume in the chosen unit', (
    tester,
  ) async {
    await _pump(
      tester,
      unit: WeightUnit.lb,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
        ],
      ),
    );

    await _menu(tester, 'finish');

    // The closed session comes back at 380 kg, which is 837.75... lb.
    expect(find.textContaining('838 lb lifted'), findsOneWidget);
  });

  testWidgets('switching the unit in the header saves it to the profile', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpLogging(tester, patches: patches);

    await tester.tap(find.byKey(const Key('unit.lb')));
    await tester.pumpAndSettle();

    expect(patches, [
      {'weightUnit': 'lb'},
    ]);
  });

  testWidgets('progress counts sets across the whole session', (tester) async {
    await _pump(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
        ],
      ),
    );

    // 3 target sets + 2 target sets = 5. Asserted through semantics because
    // the mockup's meta row shows only the bar -- a screen reader still has
    // to be able to get the number out of it.
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('1 of 5 sets'), findsOneWidget);
    semantics.dispose();
  });

  // Which set is next is one value, derived once on this screen and handed
  // to both the table and the footer. It used to be derived twice, in two
  // identical getters, and two copies of a rule are two rules: a highlight
  // that pointed at one row while the button named another would put back
  // exactly the ambiguity "Complete set N" exists to remove.
  testWidgets('the highlighted row is the set the button names', (
    tester,
  ) async {
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
        ],
      ),
    );

    // Three target sets, the first already stored: set 2 is next, and both
    // the table and the footer have to say so.
    expect(find.text('Complete set 2'), findsOneWidget);
    expect(
      tester.widgetList<SetRow>(find.byType(SetRow)).map((row) => row.active),
      [false, true, false],
    );
  });

  // The other end of the same derivation, which used to live in the panel:
  // an exercise with every set stored has no next set, so nothing is
  // highlighted and the footer offers the next exercise instead of naming a
  // set that does not exist.
  testWidgets(
    'a finished exercise highlights nothing and offers the next one',
    (tester) async {
      await _pumpLogging(
        tester,
        session: _session(
          sets: const [
            LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
            LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
            LoggedSet(exerciseId: 101, setNumber: 3, weightKg: 20, reps: 10),
          ],
        ),
      );

      expect(find.text('Next exercise'), findsOneWidget);
      expect(
        tester.widgetList<SetRow>(find.byType(SetRow)).map((row) => row.active),
        [false, false, false],
      );
    },
  );

  // The tick used to be what logged a set and started the rest timer; that
  // wiring moved off SetRow entirely in this task -- a footer button reads
  // the same drafted fields instead (logger_action.dart, a later task).
  // What is left to verify here is that an unlogged row's mark genuinely
  // reaches nothing: no call to the controller, no rest timer.
  testWidgets('an unlogged row\'s tick does not reach the controller', (
    tester,
  ) async {
    final controller = await _pumpLogging(tester);

    await tester.enterText(find.byKey(const Key('set.1.weight')), '25');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(controller.calls, isNot(contains('log:101:1:25.0:8')));
    expect(find.byKey(const Key('rest.remaining')), findsNothing);
  });

  // Same point from the other side: even a controller primed to fail a
  // write is never given the chance to, because the tap that used to reach
  // it no longer does.
  testWidgets(
    'an unlogged row\'s tick does not reach a controller primed to fail',
    (tester) async {
      final controller = await _pumpLogging(tester);
      controller.logSetError = Exception('offline');

      await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
      await tester.tap(find.byKey(const Key('set.1.tick')));
      await tester.pumpAndSettle();

      expect(controller.calls, isEmpty);
      expect(find.text('Retry'), findsNothing);
      expect(find.byKey(const Key('rest.remaining')), findsNothing);
    },
  );

  // Beyond the brief -- the panel and the pushed screen are each tested in
  // isolation, but nothing exercised the glue in session_logger_screen.dart
  // that turns the exercise on screen into the pushed screen's position and
  // total. Advancing to the SECOND exercise first is what makes it bite: an
  // off-by-one passing `index` instead of `index + 1` would read
  // "Exercise 1 of 2" here, the same text a correct first-exercise tap
  // produces -- so only the second exercise tells the two apart.
  testWidgets('opening the demo shows the exercise on screen, not the first', (
    tester,
  ) async {
    // The footer now logs the active set; pre-loading every set on the
    // first exercise is what makes it read "Next exercise" instead.
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
          LoggedSet(exerciseId: 101, setNumber: 3, weightKg: 20, reps: 10),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();
    // Next exercise lands on exercise 2's demo stage; the panel carrying the
    // thumbnail this test taps is one Start logging away.
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logpanel.demo.102')));
    await tester.pumpAndSettle();

    expect(find.text('Exercise 2 of 2'), findsOneWidget);
    expect(find.text('2 sets × 10-15 reps'), findsOneWidget);
  });

  testWidgets('finishing sends the elapsed minutes and shows a summary', (
    tester,
  ) async {
    final controller = await _pump(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
        ],
      ),
    );

    await _menu(tester, 'finish');

    // The exact minute count, not just the prefix: the fixture started 12
    // minutes ago, and a startsWith('complete:') check is satisfied just as
    // well by 'complete:0' -- so a duration that was hardcoded, negated or
    // lost with the start time would sail straight through it. The summary
    // assertion below cannot cover for that either; 380 is totalVolumeKg,
    // and durationMin is never read anywhere else in the suite.
    expect(controller.calls, contains('complete:12'));
    expect(find.byKey(const Key('logger.summary')), findsOneWidget);
    expect(find.textContaining('380'), findsOneWidget);
  });

  testWidgets('a session closed elsewhere pops the logger instead of hanging', (
    tester,
  ) async {
    final controller = await _pump(tester);
    controller.completeError = const ApiException(
      'SESSION_NOT_IN_PROGRESS',
      'This session has already been closed.',
    );

    await _menu(tester, 'finish');

    expect(find.byKey(const Key('logger.summary')), findsNothing);
    // Gone from the stack, not merely summary-less: the host route is back.
    expect(find.byType(SessionLoggerScreen), findsNothing);
    expect(find.text('open logger'), findsOneWidget);
    expect(find.text('This session was already finished.'), findsOneWidget);
  });

  testWidgets('discarding asks first, then abandons', (tester) async {
    final controller = await _pump(tester);

    await _menu(tester, 'discard');
    expect(find.text('Discard this session?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(controller.calls, contains('abandon'));
  });

  // Beyond the brief -- carried issue (a) from task 9's review: the
  // controller's _current getter throws a raw StateError once state is
  // already null, and complete() reads it up front. Two rapid Finish taps
  // dispatched before either request lands must not let the second one
  // reach the controller at all, let alone surface that StateError.
  testWidgets(
    'tapping finish twice before the first request resolves calls complete only once',
    (tester) async {
      final controller = await _pump(
        tester,
        session: _session(
          sets: const [
            LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          ],
        ),
      );
      final gate = Completer<void>();
      controller.completeGate = gate;

      await _menu(tester, 'finish');
      await _menu(tester, 'finish');
      gate.complete();
      await tester.pumpAndSettle();

      expect(
        controller.calls.where((call) => call.startsWith('complete:')).length,
        1,
      );
      // No raw StateError (or anything else) escaped unhandled.
      expect(tester.takeException(), isNull);
    },
  );

  // Beyond the brief -- carried issue (a) again, at the point where it
  // actually surfaces. The _finishing guard above stops a SECOND tap from
  // reaching the controller, so it never exercises the catch itself. This
  // does: the controller rejects the completion outright with the raw
  // StateError its _current getter throws. That must land on the same path
  // as the 409 -- pop with the plain-language message -- and never fall
  // through to the generic handler, which would leave the user standing on
  // a dead session reading "Something went wrong."
  testWidgets(
    'a StateError from complete leaves by the already-finished path',
    (tester) async {
      final controller = await _pump(tester);
      controller.completeError = StateError('No session is in progress.');

      await _menu(tester, 'finish');

      expect(find.text('This session was already finished.'), findsOneWidget);
      expect(find.text('Something went wrong.'), findsNothing);
      expect(find.byKey(const Key('logger.summary')), findsNothing);
      expect(find.byType(SessionLoggerScreen), findsNothing);
      expect(find.text('open logger'), findsOneWidget);
    },
  );

  // The same contract on the Discard side: abandon() reads _current too.
  testWidgets('a StateError from abandon leaves by the already-finished path', (
    tester,
  ) async {
    final controller = await _pump(tester);
    controller.abandonError = StateError('No session is in progress.');

    await _menu(tester, 'discard');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(controller.calls, contains('abandon'));
    expect(find.text('This session was already finished.'), findsOneWidget);
    expect(find.byType(SessionLoggerScreen), findsNothing);
    expect(find.text('open logger'), findsOneWidget);
  });

  // A named global constraint of this task: a failed finish leaves the session
  // in progress and resumable. Every other finish test either succeeds or
  // fails down the 409 / StateError already-closed path, both of which pop on
  // purpose -- so the generic branch, the one that must NOT pop, is otherwise
  // never taken. The controller keeps state intact today because complete()
  // only nulls it after its await; this is what stops a later edit from
  // adding a pop or an invalidate here and stranding a live session.
  //
  // Run over both failing branches. A named ApiException lands in the
  // `on ApiException` clause and an unnamed error in the generic `catch`;
  // they are separate code paths with the same obligation, and a test that
  // only ever threw one of them would leave the other free to grow a pop.
  for (final (kind, error, message) in <(String, Object, String)>[
    (
      'a named API failure',
      const ApiException('NETWORK', 'No connection.'),
      'No connection.',
    ),
    ('an unnamed failure', Exception('offline'), 'Something went wrong.'),
  ]) {
    testWidgets(
      'a finish that fails with $kind leaves the session in progress',
      (tester) async {
        final controller = await _pump(
          tester,
          session: _session(
            sets: const [
              LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
            ],
          ),
        );
        controller.completeError = error;

        await _menu(tester, 'finish');

        expect(find.text(message), findsOneWidget);
        // Not closed, not summarised, and above all not navigated away from:
        // the logger is still the route on top and the session is in progress.
        expect(find.byType(SessionLoggerScreen), findsOneWidget);
        expect(find.byKey(const Key('logger.summary')), findsNothing);
        expect(controller.heldSession, isNotNull);
        expect(tester.takeException(), isNull);

        // Resumable in practice, not just in state: the _finishing guard was
        // released, so a second attempt actually reaches the controller. A
        // guard left stuck would leave a session that can never be finished
        // from here. No wait for the SnackBar to clear any more: Finish moved
        // to the app bar's menu, which a bottom-anchored SnackBar never covers.
        await _menu(tester, 'finish');
        expect(
          controller.calls.where((c) => c.startsWith('complete:')).length,
          2,
        );
      },
    );
  }

  // Beyond the brief -- Discard is destructive and its request can simply
  // fail. Without a handler the future's error is unhandled, the screen does
  // not move, and the tap reads as though it did nothing at all.
  testWidgets('a discard that fails says so and keeps the session', (
    tester,
  ) async {
    final controller = await _pump(tester);
    controller.abandonError = const ApiException('NETWORK', 'No connection.');

    await _menu(tester, 'discard');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('No connection.'), findsOneWidget);
    // Still on the logger, still logging: nothing was thrown away.
    expect(find.byType(SessionLoggerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Beyond the brief -- carried issue (b): task 9's race fix made logSet
  // re-read _current AFTER its await, so a completion landing mid-write makes
  // that write throw the raw StateError. That failure path is now reached
  // through the footer button rather than the tick (a later task); what
  // stays true of the row itself is that a tap never reaches the controller
  // at all, mid-flight race or not, so nothing here can throw.
  testWidgets(
    'an unlogged row\'s tick does not reach a controller that would race mid-flight',
    (tester) async {
      final controller = await _pumpLogging(tester);
      controller.logSetError = StateError('No session is in progress.');

      await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
      await tester.tap(find.byKey(const Key('set.1.tick')));
      await tester.pumpAndSettle();

      expect(controller.calls, isEmpty);
      expect(find.text('Retry'), findsNothing);
      expect(find.byKey(const Key('rest.remaining')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // Beyond the brief -- the brief's own test list only ever confirms
  // Discard. Cancelling via "Keep going" must leave the session alone and
  // the logger on screen.
  testWidgets('cancelling discard leaves the logger open without abandoning', (
    tester,
  ) async {
    final controller = await _pump(tester);

    await _menu(tester, 'discard');
    expect(find.text('Discard this session?'), findsOneWidget);

    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();

    expect(controller.calls, isNot(contains('abandon')));
    expect(find.text('Discard this session?'), findsNothing);
    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  // Beyond the brief -- spec section 8 says a SESSION_NOT_IN_PROGRESS response
  // closes the logger and refetches. That handling sits behind the same write
  // call as every other set-write test above, so it moves with it (a later
  // task); an unlogged row's tick reaching nothing means this session stays
  // open and untouched rather than closing on a write nothing triggered.
  testWidgets(
    'an unlogged row\'s tick does not reach a controller primed to report the '
    'session closed',
    (tester) async {
      final controller = await _pumpLogging(tester);
      controller.logSetError = const ApiException(
        'SESSION_NOT_IN_PROGRESS',
        'This session has already been closed.',
      );

      await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
      await tester.tap(find.byKey(const Key('set.1.tick')));
      await tester.pumpAndSettle();

      expect(controller.calls, isEmpty);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(SessionLoggerScreen), findsOneWidget);
      expect(find.text('This session was already finished.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // Critical fix (review of task 2): _drafts.release(setNumber) has to run
  // in session_logger_screen.dart's own onUndoSet, not just be documented as
  // a later task's job -- otherwise a reopened row keeps showing the number
  // that was just undone. This is the one test that can actually catch a
  // regression here: exercise_log_panel_test.dart drives ExerciseLogPanel
  // directly and supplies its own onUndoSet, so it can never see whether
  // this screen's real handler calls release() or not.
  testWidgets('undoing a set clears its typed values from the reopened row', (
    tester,
  ) async {
    await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 22.5, reps: 10),
        ],
      ),
      last: const {},
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('set.1.weight')))
          .controller!
          .text,
      '22.5',
    );

    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('set.1.weight')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('set.1.reps')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('a 409 on an undo closes the logger too', (tester) async {
    final controller = await _pumpLogging(
      tester,
      session: _session(
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
        ],
      ),
    );
    controller.unlogSetError = const ApiException(
      'SESSION_NOT_IN_PROGRESS',
      'This session has already been closed.',
    );

    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing);
    expect(find.byType(SessionLoggerScreen), findsNothing);
    expect(find.text('open logger'), findsOneWidget);
    expect(find.text('This session was already finished.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Beyond the brief -- startedAt is the SERVER's NOW(). A phone clock behind
  // it makes DateTime.now().difference(startedAt) negative, and the route
  // rejects a negative durationMin with 400 DURATION_INVALID: the one failure
  // mode where a session genuinely cannot be finished from the phone.
  testWidgets('a clock behind the server still finishes, at zero minutes', (
    tester,
  ) async {
    final controller = await _pump(
      tester,
      session: ActiveSession(
        sessionId: 7,
        status: 'in_progress',
        sessionDate: '2026-09-08',
        startedAt: DateTime.now().add(const Duration(minutes: 90)),
      ),
    );

    // The header must not read "-90 min elapsed" either.
    expect(find.text('0 min elapsed'), findsOneWidget);

    await _menu(tester, 'finish');

    expect(controller.calls, contains('complete:0'));
    expect(find.byKey(const Key('logger.summary')), findsOneWidget);
  });

  // The logger reads the whole plan today. With a rotation it must show only
  // the day the session is on, or a Push session lists the Pull exercises too.
  testWidgets('the logger shows only the session day, not the whole plan', (
    tester,
  ) async {
    await _pumpLogging(
      tester,
      plan: _rotationPlan,
      session: _session(planDayNo: 2),
    );

    expect(find.textContaining('Push-up'), findsOneWidget);
    expect(find.text('Goblet squat'), findsNothing);
    expect(_metaPosition('Exercise 1 / 1'), findsOneWidget);
  });

  // A session stamped before migration 013 carries no planDayNo at all --
  // this is where that lands in the wiring, not just the model: the logger
  // must read the null as day 1, the same as exercisesForDay does on its own.
  testWidgets('a session with no planDayNo shows day 1 of the rotation', (
    tester,
  ) async {
    await _pumpLogging(tester, plan: _rotationPlan, session: _session());

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.textContaining('Push-up'), findsNothing);
    expect(_metaPosition('Exercise 1 / 1'), findsOneWidget);
  });

  // The ML service now refuses to generate a split with a day it cannot
  // fill, so this should not arise from a fresh plan -- but a plan saved
  // before that guard, or one whose rows were edited, still can, and
  // POST /sessions has already created the session row by the time this
  // screen sees the day is empty. A bare spinner would strand the user on a
  // screen with no AppBar, no back button and nothing to wait for.
  testWidgets(
    'a session on a day with no exercises offers a way out, not a spinner',
    (tester) async {
      await _pump(tester, plan: _rotationPlan, session: _session(planDayNo: 3));

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'an empty day is a settled state, not a loading one',
      );
      expect(find.byKey(const Key('logger.emptyDay')), findsOneWidget);
      // The same chrome as the loaded state: back out, or finish/discard the
      // session the server has already opened.
      expect(find.byKey(const Key('logger.back')), findsOneWidget);
      expect(find.byKey(const Key('logger.menu')), findsOneWidget);
    },
  );

  testWidgets('finishing a hand-picked workout offers to keep it', (
    tester,
  ) async {
    // The moment the user knows whether the workout was worth keeping. A
    // decision asked later, on another screen, is asked when they have
    // forgotten what was in it.
    await _pump(tester, session: _manualSessionWithSets());

    await _menu(tester, 'finish');

    expect(find.byKey(const Key('logger.summary')), findsOneWidget);
    expect(find.byKey(const Key('summary.toPlan')), findsOneWidget);
  });

  testWidgets(
    'finishing a plan workout offers nothing — it is already in one',
    (tester) async {
      await _pump(tester, session: _planSessionWithSets());

      await _menu(tester, 'finish');

      expect(find.byKey(const Key('logger.summary')), findsOneWidget);
      expect(find.byKey(const Key('summary.toPlan')), findsNothing);
    },
  );

  testWidgets('accepting sends the workout to the plan', (tester) async {
    final plans = RecordingPlanRepository();
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');
    await tester.tap(find.byKey(const Key('summary.toPlan')));
    await tester.pumpAndSettle();

    expect(plans.fromSessionCalls, 1);
    expect(plans.lastSessionId, 9);
  });

  testWidgets('declining changes nothing', (tester) async {
    // The default. Finishing without accepting leaves the workout a one-off,
    // which is what manual logging was always for.
    final plans = RecordingPlanRepository();
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(plans.fromSessionCalls, 0);
    // Done resolves the summary dialog false (not the true _addToPlan sends),
    // so _showSummary must still pop the screen itself -- the branch the
    // add-to-plan race fix must leave untouched.
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });

  // A barrier dismiss never runs _addToPlan, so the summary dialog resolves
  // null -- treated the same as Done's explicit false -- and _showSummary
  // must still pop the screen itself. The add-to-plan race fix touches this
  // path only by changing showDialog's type; nothing exercised it before.
  testWidgets(
    'dismissing the summary via the barrier still leaves the logger',
    (tester) async {
      await _pump(tester, session: _manualSessionWithSets());

      await _menu(tester, 'finish');
      expect(find.byKey(const Key('logger.summary')), findsOneWidget);

      // Outside the AlertDialog's own bounds, on the modal barrier that
      // showDialog leaves dismissible by default.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logger.summary')), findsNothing);
      expect(find.byType(SessionLoggerScreen), findsNothing);
    },
  );

  testWidgets('a failed write says so and does not claim the plan changed', (
    tester,
  ) async {
    final plans = RecordingPlanRepository(
      error: const ApiException('NETWORK_ERROR', 'Could not reach the server.'),
    );
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');
    await tester.tap(find.byKey(const Key('summary.toPlan')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the server.'), findsOneWidget);
  });

  // The summary dialog -- and the whole logger route behind it -- pops
  // synchronously on tap, while planFromSession is still in flight. That is
  // the ordinary case in production, not a rare race: nothing here holds the
  // route open for the request. A refresh that depends on this State still
  // being alive when the request resolves would be silently lost on every
  // real tap -- and lost silently: invalidating through a disposed State's
  // own `ref` throws, which is caught by the same handler and (if nothing
  // else guards it) would surface as an unrelated error message for a write
  // that actually succeeded.
  //
  // Asserting only on the absence of that message would not by itself prove
  // the cache was refreshed: a handler that guards the catch block against a
  // disposed State (stopping the wrong message) but still invalidates
  // through `ref` would swallow the same throw just as quietly, and pass a
  // test that checked only for the symptom. So this forces a fresh read of
  // activePlanProvider afterwards and counts how many times its override
  // actually ran -- invalidate() only marks a provider to recompute on its
  // next access, so a read that does not re-run the override proves the
  // invalidation never reached it.
  testWidgets(
    'accepting still invalidates the plan cache after the screen has already closed',
    (tester) async {
      final gate = Completer<WorkoutPlan>();
      final plans = RecordingPlanRepository(gate: gate);
      var activePlanReads = 0;
      await _pump(
        tester,
        session: _manualSessionWithSets(),
        plans: plans,
        onActivePlanRead: () => activePlanReads++,
      );
      final readsBeforeAccept = activePlanReads;

      await _menu(tester, 'finish');
      await tester.tap(find.byKey(const Key('summary.toPlan')));
      // Lets both pops -- the dialog's, and the logger route's behind it --
      // actually finish. The request stays gated throughout, so nothing here
      // depends on it resolving yet.
      await tester.pumpAndSettle();

      expect(
        find.byType(SessionLoggerScreen),
        findsNothing,
        reason:
            'the route, and the State handling this request, must '
            'already be gone',
      );
      // Read from a surviving element -- the host screen behind the logger --
      // since the logger's own context is exactly what is gone.
      final container = ProviderScope.containerOf(
        tester.element(find.text('open logger')),
      );

      gate.complete(
        const WorkoutPlan(
          planId: 9,
          name: 'My Full Body',
          splitStyle: 'full_body',
          daysPerWeek: 1,
          sessionLengthMin: 45,
          weekNo: 1,
          exercises: [],
          source: 'custom',
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Something went wrong.'), findsNothing);

      await container.read(activePlanProvider.future);
      expect(
        activePlanReads,
        greaterThan(readsBeforeAccept),
        reason:
            'the plan cache must be invalidated even though the State '
            'handling the write is already gone',
      );
    },
  );

  // The same disposed-State race as above, but the request itself fails
  // rather than succeeding -- and this is the ORDINARY case, not a rare one:
  // the route pops synchronously on tap, so on any connection slower than the
  // pop animation there is no `mounted` screen left by the time the failure
  // lands. That is precisely why the messenger is captured before the first
  // await: it belongs to the host scaffold the pop returns to, which is still
  // there. Gating the message on `mounted` as well threw that away and left
  // the only irreversible action in this flow reporting nothing at all.
  testWidgets(
    'a write that fails after the screen has already closed still says so',
    (tester) async {
      final gate = Completer<WorkoutPlan>();
      final plans = RecordingPlanRepository(gate: gate);
      await _pump(tester, session: _manualSessionWithSets(), plans: plans);

      await _menu(tester, 'finish');
      await tester.tap(find.byKey(const Key('summary.toPlan')));
      await tester.pumpAndSettle();

      expect(find.byType(SessionLoggerScreen), findsNothing);

      gate.completeError(
        const ApiException('NETWORK_ERROR', 'Could not reach the server.'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Could not reach the server.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a write that lands after the screen has already closed still confirms it',
    (tester) async {
      // The success half of the same race. A plan quietly rewritten with no
      // acknowledgement is indistinguishable from one that was not.
      final gate = Completer<WorkoutPlan>();
      final plans = RecordingPlanRepository(gate: gate);
      await _pump(tester, session: _manualSessionWithSets(), plans: plans);

      await _menu(tester, 'finish');
      await tester.tap(find.byKey(const Key('summary.toPlan')));
      await tester.pumpAndSettle();

      expect(find.byType(SessionLoggerScreen), findsNothing);

      gate.complete(
        const WorkoutPlan(
          planId: 9,
          name: 'My Full Body',
          splitStyle: 'full_body',
          daysPerWeek: 1,
          sessionLengthMin: 45,
          weekNo: 1,
          exercises: [],
          source: 'custom',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Added to My Full Body.'), findsOneWidget);
    },
  );

  testWidgets('with no plan of the user\'s own, the offer is to make one', (
    tester,
  ) async {
    // Spec s4: "Make this my plan" when there is no custom plan yet. The two
    // labels describe different acts -- one starts a plan, the other adds to
    // the one already being followed -- and a single label for both hides a
    // replacement behind the gentler of the two.
    final plans = RecordingPlanRepository();
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');

    expect(find.text('Make this my plan'), findsOneWidget);
    expect(find.text('Add to my plan'), findsNothing);
  });

  testWidgets('with a plan of their own already, the offer is to add to it', (
    tester,
  ) async {
    final plans = RecordingPlanRepository(active: _customPlan);
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');

    expect(find.text('Add to my plan'), findsOneWidget);
    expect(find.text('Make this my plan'), findsNothing);
  });

  testWidgets('replacing a generated plan is asked for, and names it', (
    tester,
  ) async {
    // The destructive direction. Accepting over a generated plan deactivates
    // it and puts a one-day custom plan in its place; plan history is out of
    // scope, so it does not come back. The generator already asks before
    // replacing a plan the user built -- this is the same question, asked in
    // the direction that was silent.
    final plans = RecordingPlanRepository(active: _generatedPlan);
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');
    await tester.tap(find.byKey(const Key('summary.toPlan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('summary.replacePlan')), findsOneWidget);
    // Scoped to the dialog: the logger's own chrome behind it also carries
    // the plan name, so an unscoped finder would pass on the wrong widget.
    expect(
      find.descendant(
        of: find.byKey(const Key('summary.replacePlan')),
        matching: find.textContaining('Week 1 — Full body'),
      ),
      findsOneWidget,
      reason: 'the question has to name what goes',
    );
    expect(plans.fromSessionCalls, 0, reason: 'nothing is written until asked');
  });

  testWidgets('keeping the generated plan writes nothing', (tester) async {
    final plans = RecordingPlanRepository(active: _generatedPlan);
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');
    await tester.tap(find.byKey(const Key('summary.toPlan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(plans.fromSessionCalls, 0);
    // The session is finished either way, so the logger still has to leave --
    // _showSummary handed its own pop to _addToPlan the moment the offer was
    // tapped, and a cancelled write must not strand the user on a logger
    // whose session is already closed.
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });

  testWidgets('confirming replaces the generated plan', (tester) async {
    final plans = RecordingPlanRepository(active: _generatedPlan);
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');
    await tester.tap(find.byKey(const Key('summary.toPlan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace it'));
    await tester.pumpAndSettle();

    expect(plans.fromSessionCalls, 1);
    expect(plans.lastSessionId, 9);
  });

  testWidgets('dismissing the day sheet adds no day at all', (tester) async {
    // Dismissal is not a vote for "a new day": that is its own row on the
    // sheet. Removing a day from a custom plan is out of scope, so a day
    // appended by a stray tap outside the sheet would be permanent.
    final plans = RecordingPlanRepository(active: _customPlan);
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');
    await tester.tap(find.byKey(const Key('summary.toPlan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('addToPlan.newDay')), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(plans.fromSessionCalls, 0);
    expect(
      find.byType(SessionLoggerScreen),
      findsNothing,
      reason: 'the session is finished either way',
    );
  });

  testWidgets('an existing custom plan asks which day the workout becomes', (
    tester,
  ) async {
    final plans = RecordingPlanRepository(
      active: const WorkoutPlan(
        planId: 9,
        name: 'My Full Body',
        splitStyle: 'full_body',
        daysPerWeek: 1,
        sessionLengthMin: 45,
        weekNo: 1,
        source: 'custom',
        exercises: [
          PlanExercise(
            planExerciseId: 1,
            exerciseId: 101,
            name: 'Bench press',
            muscleGroup: 'chest',
            orderNo: 1,
            targetSets: 3,
            targetReps: '8-12',
            dayNo: 1,
          ),
        ],
      ),
    );
    await _pump(tester, session: _manualSessionWithSets(), plans: plans);

    await _menu(tester, 'finish');
    await tester.tap(find.byKey(const Key('summary.toPlan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addToPlan.newDay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('addToPlan.day.1')));
    await tester.pumpAndSettle();

    expect(plans.lastDayNo, 1);
    // The handoff this race fix depends on: _showSummary sees the dialog
    // resolve true and skips its own pop, leaving _addToPlan to pop the
    // screen itself once the sheet -- not the dialog -- has actually
    // resolved. Nothing above proves that pop ever happened.
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });

  group('encouragement', () {
    const squatDone = [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
      LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
      LoggedSet(exerciseId: 101, setNumber: 3, weightKg: 20, reps: 10),
    ];

    testWidgets('says nothing while the exercise has sets left', (
      tester,
    ) async {
      await _pumpLogging(tester);
      expect(find.byKey(const Key('logger.encouragement')), findsNothing);
    });

    testWidgets('appears when the last set of an exercise is logged', (
      tester,
    ) async {
      await _pumpLogging(
        tester,
        session: _session(sets: squatDone.sublist(0, 2)),
      );
      expect(find.byKey(const Key('logger.encouragement')), findsNothing);

      // Complete set 3 -- the one the footer names.
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();

      // Two exercises in the plan, so the first finished is halfway.
      expect(find.byKey(const Key('logger.encouragement')), findsOneWidget);
      // Which halfway line shows varies by session; every one gives the count.
      expect(find.textContaining('1 of 2'), findsOneWidget);
      expect(find.text('Up next: Push-up'), findsOneWidget);
    });

    testWidgets('goes away when a set of the exercise is reopened', (
      tester,
    ) async {
      await _pumpLogging(tester, session: _session(sets: squatDone));
      expect(find.byKey(const Key('logger.encouragement')), findsOneWidget);

      await tester.tap(find.byKey(const Key('set.3.row')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logger.encouragement')), findsNothing);
    });

    testWidgets('closes the session out once every set is done', (
      tester,
    ) async {
      await _pumpLogging(
        tester,
        session: _session(
          sets: const [
            ...squatDone,
            LoggedSet(exerciseId: 102, setNumber: 1, reps: 12),
            LoggedSet(exerciseId: 102, setNumber: 2, reps: 12),
          ],
        ),
      );
      // Which closing line shows varies by session; every one points at Finish.
      expect(
        find.textContaining('Tap Finish session to save it.'),
        findsOneWidget,
      );
    });

    testWidgets('is not shown on the demo stage', (tester) async {
      await _pump(tester, session: _session(sets: squatDone));
      expect(find.byKey(const Key('logger.demo')), findsOneWidget);
      expect(find.byKey(const Key('logger.encouragement')), findsNothing);
    });
  });

  group('restart this exercise', () {
    const twoSquatSets = [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
      LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
    ];
    // Logged against the next exercise, so a restart that touched more than
    // the exercise on screen would show up in the calls.
    const pushUpSet = LoggedSet(exerciseId: 102, setNumber: 1, reps: 12);

    Future<bool> restartEnabled(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('logger.menu')));
      await tester.pumpAndSettle();
      final enabled = tester
          .widget<PopupMenuItem<String>>(
            find.byKey(const Key('logger.restart')),
          )
          .enabled;
      // Close the menu again without choosing anything.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      return enabled;
    }

    testWidgets('asks first, naming the exercise and how many sets go', (
      tester,
    ) async {
      await _pumpLogging(tester, session: _session(sets: twoSquatSets));

      await _menu(tester, 'restart');

      expect(find.text('Restart Goblet squat?'), findsOneWidget);
      expect(
        find.text(
          'Your 2 logged sets for this exercise will be cleared. '
          'The rest of your session is kept.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('one logged set is singular in the question', (tester) async {
      await _pumpLogging(
        tester,
        session: _session(sets: twoSquatSets.sublist(0, 1)),
      );

      await _menu(tester, 'restart');

      expect(
        find.textContaining('Your 1 logged set for this exercise'),
        findsOneWidget,
      );
    });

    testWidgets('clears only the exercise on screen and stays on its table', (
      tester,
    ) async {
      final controller = await _pumpLogging(
        tester,
        session: _session(sets: const [...twoSquatSets, pushUpSet]),
        last: const {},
      );

      await _menu(tester, 'restart');
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(controller.calls, containsAll(['unlog:101:1', 'unlog:101:2']));
      expect(controller.calls, isNot(contains('unlog:102:1')));
      expect(controller.calls, isNot(contains('abandon')));
      // Still logging, back at set 1, with the cleared rows emptied.
      expect(find.byType(SessionLoggerScreen), findsOneWidget);
      expect(find.text('Complete set 1'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('set.1.reps')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('Keep leaves every set where it was', (tester) async {
      final controller = await _pumpLogging(
        tester,
        session: _session(sets: twoSquatSets),
      );

      await _menu(tester, 'restart');
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(controller.calls.where((c) => c.startsWith('unlog')), isEmpty);
      expect(find.text('Complete set 3'), findsOneWidget);
    });

    testWidgets('stops a rest that was counting down', (tester) async {
      await _pumpLogging(tester, session: _session(sets: twoSquatSets));
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      expect(find.byType(RestTimer), findsOneWidget);

      await _menu(tester, 'restart');
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(find.byType(RestTimer), findsNothing);
    });

    testWidgets('is unavailable before anything is logged on the exercise', (
      tester,
    ) async {
      await _pumpLogging(tester, session: _session(sets: const [pushUpSet]));
      expect(await restartEnabled(tester), isFalse);
    });

    testWidgets('is unavailable on the demo stage', (tester) async {
      await _pump(tester, session: _session(sets: twoSquatSets));
      expect(await restartEnabled(tester), isFalse);
    });

    testWidgets('a restart that fails says so and keeps the session', (
      tester,
    ) async {
      final controller = await _pumpLogging(
        tester,
        session: _session(sets: twoSquatSets),
      );
      controller.unlogSetError = Exception('offline');

      await _menu(tester, 'restart');
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't finish restarting Goblet squat."),
        findsOneWidget,
      );
      expect(find.byType(SessionLoggerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a session closed elsewhere leaves the logger', (tester) async {
      final controller = await _pumpLogging(
        tester,
        session: _session(sets: twoSquatSets),
      );
      controller.unlogSetError = const ApiException(
        'SESSION_NOT_IN_PROGRESS',
        'This session has already been closed.',
      );

      await _menu(tester, 'restart');
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionLoggerScreen), findsNothing);
      expect(find.text('This session was already finished.'), findsOneWidget);
    });
  });

  group('rest time', () {
    testWidgets('a rest starts from the saved rest time', (tester) async {
      await _pumpLogging(tester, training: FakeTrainingSettings(120));

      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
        '2:00',
      );
    });

    testWidgets('the menu names the rest time and opens its sheet', (
      tester,
    ) async {
      await _pump(tester, training: FakeTrainingSettings(150));

      await tester.tap(find.byKey(const Key('logger.menu')));
      await tester.pumpAndSettle();
      expect(find.text('Rest time: 2:30'), findsOneWidget);

      await tester.tap(find.byKey(const Key('logger.restTime')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rest.sheet')), findsOneWidget);
      // Opened before any rest is running, so there is no countdown to show.
      expect(find.byKey(const Key('rest.sheet.remaining')), findsNothing);
    });

    testWidgets('a default chosen from the menu is the next rest\'s length', (
      tester,
    ) async {
      final training = FakeTrainingSettings();
      await _pumpLogging(tester, training: training);

      await _menu(tester, 'restTime');
      await tester.tap(find.byKey(const Key('rest.preset.60')));
      await tester.pumpAndSettle();
      expect(training.writes, [60]);
      // Close the sheet the way a user would.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
        '1:00',
      );
    });

    testWidgets('the running rest\'s tag opens the sheet with its countdown', (
      tester,
    ) async {
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('rest.open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('rest.sheet.remaining')), findsOneWidget);
      await tester.tap(find.byKey(const Key('rest.skip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RestTimer), findsNothing);
    });

    // The countdown works from the moment the rest ends, not from ticks.
    testWidgets('a rest counts down with the clock', (tester) async {
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      await tester.pump(const Duration(seconds: 30));

      expect(
        tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
        '1:00',
      );
    });

    testWidgets('+30s from the sheet adds to the running rest', (tester) async {
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('rest.open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('rest.plus')));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
        '2:00',
      );
    });

    testWidgets('−30s down to nothing ends the rest and closes the sheet', (
      tester,
    ) async {
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 70)); // 0:20 left

      await tester.tap(find.byKey(const Key('rest.open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('rest.minus')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('rest.sheet')), findsNothing);
      expect(find.byKey(const Key('rest.remaining')), findsNothing);
    });

    testWidgets('the sheet closes itself when the rest runs out', (
      tester,
    ) async {
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rest.open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pump(const Duration(seconds: 90));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('rest.sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the end of a rest', () {
    testWidgets(
      'running out buzzes once, says "Rest over", shows it for 5 seconds',
      (tester) async {
        final haptics = _recordHaptics(tester);
        await _pumpLogging(tester);
        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pump();
        tester.takeAnnouncements();

        await tester.pump(const Duration(seconds: 90));

        expect(haptics, ['HapticFeedback.vibrate']);
        expect(
          tester.takeAnnouncements().map((a) => a.message),
          contains('Rest over'),
        );
        expect(find.byKey(const Key('rest.over')), findsOneWidget);

        await tester.pump(const Duration(seconds: 4));
        expect(find.byKey(const Key('rest.over')), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const Key('rest.over')), findsNothing);
        expect(find.byType(RestTimer), findsNothing);

        await tester.pump(const Duration(seconds: 30));
        expect(haptics, hasLength(1));
      },
    );

    testWidgets('Skip ends it quietly', (tester) async {
      final haptics = _recordHaptics(tester);
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('rest.open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('rest.skip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(haptics, isEmpty);
      expect(find.byKey(const Key('rest.over')), findsNothing);
      expect(find.byType(RestTimer), findsNothing);
    });

    testWidgets('−30s down to nothing ends it quietly', (tester) async {
      final haptics = _recordHaptics(tester);
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 70));

      await tester.tap(find.byKey(const Key('rest.open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('rest.minus')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(haptics, isEmpty);
      expect(find.byKey(const Key('rest.over')), findsNothing);
    });

    testWidgets('a set logged during "Rest over" starts a fresh rest', (
      tester,
    ) async {
      _recordHaptics(tester);
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 90));
      expect(find.byKey(const Key('rest.over')), findsOneWidget);

      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      expect(find.byKey(const Key('rest.over')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
        '1:30',
      );
    });

    testWidgets('a second set mid-rest restarts the rest at full length', (
      tester,
    ) async {
      await _pumpLogging(tester);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));

      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
        '1:30',
      );
    });
  });

  group('the rest alert', () {
    testWidgets('going away mid-rest schedules one alert for its end', (
      tester,
    ) async {
      final alerts = FakeRestAlertScheduler();
      await _pumpLogging(tester, alerts: alerts);
      final started = tester.binding.clock.now();
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      await _background(tester);

      expect(alerts.scheduled, hasLength(1));
      expect(
        alerts.scheduled.single.at,
        started.add(const Duration(seconds: 90)),
      );
      expect(alerts.scheduled.single.title, 'Rest over');
      expect(
        alerts.scheduled.single.body,
        'Next: set 2 of ${_plan.exercises.first.name}',
      );
    });

    testWidgets('the alert names the exercise on screen', (tester) async {
      final alerts = FakeRestAlertScheduler();
      await _pumpLogging(tester, alerts: alerts);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      // The rest carries across exercises, so the alert has to follow the
      // move rather than keep the body it would have had at the set.
      await tester.tap(find.byKey(const Key('logger.position')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('jump.102')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await _background(tester);

      expect(alerts.scheduled, hasLength(1));
      expect(
        alerts.scheduled.single.body,
        'Next: set 1 of ${_plan.exercises[1].name}',
      );
    });

    testWidgets('coming back withdraws it', (tester) async {
      final alerts = FakeRestAlertScheduler();
      await _pumpLogging(tester, alerts: alerts);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await _background(tester);
      final cancelsBefore = alerts.cancels;

      await _foreground(tester);

      expect(alerts.cancels, greaterThan(cancelsBefore));
      expect(alerts.scheduled, hasLength(1));
    });

    testWidgets('no alert without a rest running', (tester) async {
      final alerts = FakeRestAlertScheduler();
      await _pumpLogging(tester, alerts: alerts);

      await _background(tester);

      expect(alerts.scheduled, isEmpty);
    });

    testWidgets('no alert when switched off', (tester) async {
      final alerts = FakeRestAlertScheduler();
      final store = RestAlertStore(backing: InMemorySecureStore());
      await store.setEnabled(false);
      await _pumpLogging(tester, alerts: alerts, alertStore: store);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      await _background(tester);

      expect(alerts.scheduled, isEmpty);
    });

    testWidgets('no alert without permission', (tester) async {
      final alerts = FakeRestAlertScheduler(granted: false);
      final store = RestAlertStore(backing: InMemorySecureStore());
      await store.markAsked();
      await _pumpLogging(tester, alerts: alerts, alertStore: store);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      await _background(tester);

      expect(alerts.scheduled, isEmpty);
    });

    testWidgets(
      'a rest that ran out while away shows "Rest over" on return, no buzz',
      (tester) async {
        final haptics = _recordHaptics(tester);
        await _pumpLogging(tester);
        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pump();
        await _background(tester);

        await tester.pump(const Duration(seconds: 120));
        await _foreground(tester);

        expect(find.byKey(const Key('rest.over')), findsOneWidget);
        expect(haptics, isEmpty);
      },
    );

    testWidgets('the first rest asks for permission, once per phone', (
      tester,
    ) async {
      final alerts = FakeRestAlertScheduler(granted: false);
      final store = RestAlertStore(backing: InMemorySecureStore());
      await _pumpLogging(tester, alerts: alerts, alertStore: store);

      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump();
      expect(alerts.requests, 1);
      expect(await store.asked(), isTrue);

      // The next set: no second prompt.
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump();
      expect(alerts.requests, 1);
    });

    testWidgets('a set still saving when the phone locks gets its own alert', (
      tester,
    ) async {
      final alerts = FakeRestAlertScheduler();
      final controller = await _pumpLogging(tester, alerts: alerts);
      final gate = Completer<void>();
      controller.logSetGate = gate;
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();

      // Locked before the server answered: no rest yet, so nothing to alert.
      await _background(tester);
      expect(alerts.scheduled, isEmpty);

      final started = tester.binding.clock.now();
      gate.complete();
      await tester.pump();

      expect(alerts.scheduled, hasLength(1));
      expect(
        alerts.scheduled.single.at,
        started.add(const Duration(seconds: 90)),
      );
    });

    testWidgets(
      'a set saved while locked mid-rest moves the alert to its end',
      (tester) async {
        final alerts = FakeRestAlertScheduler();
        final controller = await _pumpLogging(tester, alerts: alerts);
        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 30));

        final gate = Completer<void>();
        controller.logSetGate = gate;
        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pump();
        // The first rest is still running, so locking schedules its end.
        await _background(tester);
        expect(alerts.scheduled, hasLength(1));

        final started = tester.binding.clock.now();
        gate.complete();
        await tester.pump();

        expect(
          alerts.scheduled.last.at,
          started.add(const Duration(seconds: 90)),
        );
        expect(alerts.events.last, 'schedule', reason: 'nothing cancels it');
      },
    );

    testWidgets('a set saved while locked never uses up the one prompt', (
      tester,
    ) async {
      final alerts = FakeRestAlertScheduler(granted: false);
      final store = RestAlertStore(backing: InMemorySecureStore());
      final controller = await _pumpLogging(
        tester,
        alerts: alerts,
        alertStore: store,
      );
      final gate = Completer<void>();
      controller.logSetGate = gate;
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await _background(tester);

      gate.complete();
      await tester.pump();
      await tester.pump();

      // Android blocks a prompt from the background: asking now would spend
      // the single ask on a dialog nobody sees.
      expect(alerts.requests, 0);
      expect(await store.asked(), isFalse);
    });

    testWidgets('never asks when permission is already there', (tester) async {
      final alerts = FakeRestAlertScheduler();
      await _pumpLogging(tester, alerts: alerts);

      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump();

      expect(alerts.requests, 0);
    });

    // Finish tapped mid-rest, then the screen goes off before the server
    // answers: the alert scheduled at lock time must not fire "Rest over"
    // over a workout that has already finished.
    testWidgets('a finish that lands while away withdraws the alert', (
      tester,
    ) async {
      final alerts = FakeRestAlertScheduler();
      final controller = await _pumpLogging(tester, alerts: alerts);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      final gate = Completer<void>();
      controller.completeGate = gate;

      await _menu(tester, 'finish');
      await _background(tester);
      expect(alerts.events, ['schedule']);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(alerts.events, ['schedule', 'cancel']);
    });

    // The same, for the two other ways out that never reach Finish's end of
    // the rest: Discard, and a session already closed somewhere else. Both
    // pop the screen, but a locked phone draws no frames, so the pop -- and
    // the dispose that would cancel -- waits for the user to come back.
    testWidgets('a discard that lands while away withdraws the alert', (
      tester,
    ) async {
      final alerts = FakeRestAlertScheduler();
      final controller = await _pumpLogging(tester, alerts: alerts);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      final gate = Completer<void>();
      controller.abandonGate = gate;

      await _menu(tester, 'discard');
      await tester.tap(find.text('Discard'));
      await tester.pump();
      await _background(tester);
      expect(alerts.events, ['schedule']);

      gate.complete();
      await tester.pump();

      expect(alerts.events, ['schedule', 'cancel']);
    });

    testWidgets(
      'a session found closed elsewhere while away withdraws the alert',
      (tester) async {
        final alerts = FakeRestAlertScheduler();
        final controller = await _pumpLogging(tester, alerts: alerts);
        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pump();
        final gate = Completer<void>();
        controller.completeGate = gate;
        controller.completeError = const ApiException(
          'SESSION_NOT_IN_PROGRESS',
          'This session has already been closed.',
        );

        await _menu(tester, 'finish');
        await _background(tester);
        expect(alerts.events, ['schedule']);

        gate.complete();
        await tester.pump();

        expect(alerts.events, ['schedule', 'cancel']);
      },
    );
  });

  // A user reading the demo who decides "too hard for me" used to back out
  // through every exercise, change it on the Plan tab, resume and jump back.
  group('switch exercise', () {
    const boxSquat = ExerciseAlternative(
      exerciseId: 201,
      name: 'Box squat',
      muscleGroup: 'quadriceps',
    );
    const inclinePushUp = ExerciseAlternative(
      exerciseId: 202,
      name: 'Incline push-up',
      muscleGroup: 'chest',
    );

    /// [_plan] with one row's exercise replaced, as the server answers a swap:
    /// the same plan row, slot, sets and reps, holding another exercise.
    WorkoutPlan swappedPlan(int planExerciseId, ExerciseAlternative to) =>
        WorkoutPlan(
          planId: _plan.planId,
          name: _plan.name,
          splitStyle: _plan.splitStyle,
          daysPerWeek: _plan.daysPerWeek,
          sessionLengthMin: _plan.sessionLengthMin,
          weekNo: _plan.weekNo,
          exercises: [
            for (final e in _plan.exercises)
              e.planExerciseId == planExerciseId
                  ? PlanExercise(
                      planExerciseId: e.planExerciseId,
                      exerciseId: to.exerciseId,
                      name: to.name,
                      muscleGroup: to.muscleGroup,
                      orderNo: e.orderNo,
                      targetSets: e.targetSets,
                      targetReps: e.targetReps,
                    )
                  : e,
          ],
        );

    RecordingPlanRepository squatPlans() => RecordingPlanRepository(
      active: _plan,
      swapped: swappedPlan(601, boxSquat),
      alternativeRows: const [boxSquat],
    );

    /// Picks [alt] in the open sheet and confirms it from the preview.
    Future<void> choose(WidgetTester tester, ExerciseAlternative alt) async {
      await tester.tap(find.byKey(Key('swap.alt.${alt.exerciseId}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('swap.preview.confirm')));
      await tester.pump();
    }

    testWidgets('the demo offers a switch that opens the swap sheet', (
      tester,
    ) async {
      await _pump(tester, plans: squatPlans());

      final link = find.byKey(const Key('logger.switch'));
      expect(link, findsOneWidget);
      expect(find.text('Not for you? Switch exercise'), findsOneWidget);
      expect(find.bySemanticsLabel('Switch exercise'), findsOneWidget);
      final size = tester.getSize(link);
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.text('Replace Goblet squat'), findsOneWidget);
      expect(
        find.text('Changes your plan from now on, not just today.'),
        findsOneWidget,
      );
    });

    testWidgets('choosing an alternative swaps it in at the same position', (
      tester,
    ) async {
      final plans = squatPlans();
      await _pump(tester, plans: plans);

      await tester.tap(find.byKey(const Key('logger.switch')));
      await tester.pumpAndSettle();
      await choose(tester, boxSquat);

      // The screen stays itself while the plan refetches -- no spinner in
      // place of the whole logger for the frame the new plan is in flight.
      expect(find.byKey(const Key('logger.menu')), findsOneWidget);

      await tester.pumpAndSettle();

      expect(plans.swaps, [(601, 201)]);
      expect(find.byKey(const Key('logger.demo')), findsOneWidget);
      expect(find.text('Detail 201'), findsOneWidget);
      expect(_metaPosition('Exercise 1 / 2'), findsOneWidget);
      expect(find.text('Swapped to Box squat'), findsOneWidget);
    });

    testWidgets('a dismissed sheet changes nothing', (tester) async {
      final plans = squatPlans();
      await _pump(tester, plans: plans);

      await tester.tap(find.byKey(const Key('logger.switch')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(plans.swaps, isEmpty);
      expect(find.text('Detail 101'), findsOneWidget);
      expect(find.textContaining('Swapped to'), findsNothing);
    });

    testWidgets('once a set is logged the switch is off, and says why', (
      tester,
    ) async {
      await _pump(
        tester,
        plans: squatPlans(),
        session: _session(
          sets: const [
            LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
          ],
        ),
      );

      // On the demo, where the link would be: absent here means absent.
      expect(find.byKey(const Key('logger.demo')), findsOneWidget);
      expect(find.byKey(const Key('logger.switch')), findsNothing);

      await tester.tap(find.byKey(const Key('logger.menu')));
      await tester.pumpAndSettle();

      final item = tester.widget<PopupMenuItem<String>>(
        find.byKey(const Key('logger.switch.menu')),
      );
      expect(item.enabled, isFalse);
      expect(find.text('Switch exercise'), findsOneWidget);
      expect(find.text("You've logged sets on this one"), findsOneWidget);
    });

    testWidgets('a session from a chosen list has nothing to switch', (
      tester,
    ) async {
      await _pump(tester, session: _manualSession, plan: null);

      expect(find.byKey(const Key('logger.switch')), findsNothing);

      await tester.tap(find.byKey(const Key('logger.menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('logger.switch.menu')), findsNothing);
    });

    testWidgets(
      'a switch from the table drops what was typed for the old one',
      (tester) async {
        await _pump(tester, plans: squatPlans());
        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('set.1.weight')), '20');
        await tester.enterText(find.byKey(const Key('set.1.reps')), '10');

        await _menu(tester, 'switch.menu');
        await choose(tester, boxSquat);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('logger.demo')), findsOneWidget);
        expect(find.text('Detail 201'), findsOneWidget);

        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pumpAndSettle();
        for (final field in ['set.1.weight', 'set.1.reps']) {
          expect(
            tester.widget<TextField>(find.byKey(Key(field))).controller!.text,
            isEmpty,
            reason: '$field was typed against Goblet squat, not Box squat',
          );
        }
      },
    );

    testWidgets(
      'a tap outside mid-swap leaves the sheet open, and the switch lands clean',
      (tester) async {
        final gate = Completer<void>();
        final plans = RecordingPlanRepository(
          active: _plan,
          swapped: swappedPlan(601, boxSquat),
          swapGate: gate,
          alternativeRows: const [boxSquat],
        );
        await _pump(tester, plans: plans);
        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('set.1.weight')), '20');
        await tester.enterText(find.byKey(const Key('set.1.reps')), '10');

        await _menu(tester, 'switch.menu');
        await choose(tester, boxSquat);
        // The sheet looks stuck on a slow connection; the user taps outside.
        // It stays: closed now, the swap would land with nothing to say so.
        // Not pumpAndSettle: the confirm button spins until the swap lands.
        await tester.tapAt(const Offset(5, 5));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ExerciseSwapSheet), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();

        expect(plans.swaps, [(601, 201)]);
        expect(find.byKey(const Key('logger.demo')), findsOneWidget);
        expect(find.text('Swapped to Box squat'), findsOneWidget);
        await tester.tap(find.byKey(const Key('logger.primary')));
        await tester.pumpAndSettle();
        // The empty fields belong to the new exercise, not to a table that
        // never changed.
        expect(find.text('Box squat'), findsWidgets);
        for (final field in ['set.1.weight', 'set.1.reps']) {
          expect(
            tester.widget<TextField>(find.byKey(Key(field))).controller!.text,
            isEmpty,
            reason: '$field was typed against Goblet squat, not Box squat',
          );
        }
      },
    );

    testWidgets('a running rest carries on through a switch', (tester) async {
      final plans = RecordingPlanRepository(
        active: _plan,
        swapped: swappedPlan(602, inclinePushUp),
        alternativeRows: const [inclinePushUp],
      );
      await _pump(
        tester,
        plans: plans,
        session: _session(
          sets: const [
            LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
            LoggedSet(exerciseId: 101, setNumber: 2, weightKg: 20, reps: 10),
          ],
        ),
      );
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('set.3.weight')), '20');
      await tester.enterText(find.byKey(const Key('set.3.reps')), '10');
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump();
      // Next exercise: Push-up's demo, untouched, with the rest running.
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
        '1:30',
      );

      await tester.tap(find.byKey(const Key('logger.switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await choose(tester, inclinePushUp);
      // 400 + 400 + 200 ms so far: one whole second of rest gone, no more.
      await tester.pump(const Duration(milliseconds: 200));

      expect(plans.swaps, [(602, 202)]);
      expect(find.text('Detail 202'), findsOneWidget);
      // Position 2, not the index's default 0: the switch kept it.
      expect(_metaPosition('Exercise 2 / 2'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data,
        '1:29',
      );
    });
    testWidgets('the switch waits for the new plan before it shows', (
      tester,
    ) async {
      final refetch = Completer<void>();
      final plans = RecordingPlanRepository(
        active: _plan,
        swapped: swappedPlan(601, boxSquat),
        refetchGate: refetch,
        alternativeRows: const [boxSquat],
      );
      await _pump(tester, plans: plans);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();

      await _menu(tester, 'switch.menu');
      await choose(tester, boxSquat);
      await tester.pumpAndSettle();

      // The sheet has closed and the server has swapped, but the plan on
      // screen is still the old one: nothing may claim the switch yet.
      expect(plans.swaps, [(601, 201)]);
      expect(find.byType(ExerciseSwapSheet), findsNothing);
      expect(find.byKey(const Key('logger.demo')), findsNothing);
      expect(find.textContaining('Swapped to'), findsNothing);
      expect(find.text('Goblet squat'), findsWidgets);

      refetch.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logger.demo')), findsOneWidget);
      expect(find.text('Detail 201'), findsOneWidget);
      expect(find.text('Swapped to Box squat'), findsOneWidget);
    });

    testWidgets('a refetch that fails says so instead of "Swapped to"', (
      tester,
    ) async {
      final plans = RecordingPlanRepository(
        active: _plan,
        swapped: swappedPlan(601, boxSquat),
        refetchError: const ApiException(
          'PLAN_LOAD_FAILED',
          'Could not load your plan.',
        ),
        alternativeRows: const [boxSquat],
      );
      await _pump(tester, plans: plans);
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();

      await _menu(tester, 'switch.menu');
      await choose(tester, boxSquat);
      await tester.pumpAndSettle();

      expect(find.text('Could not load your plan.'), findsOneWidget);
      expect(find.textContaining('Swapped to'), findsNothing);
      // Stayed put: the old exercise's table, not a demo of either.
      expect(find.byKey(const Key('logger.demo')), findsNothing);
      expect(find.byKey(const Key('set.1.weight')), findsOneWidget);
    });

    testWidgets('"Swapped to" floats clear of Start logging', (tester) async {
      await _pump(tester, plans: squatPlans());

      await tester.tap(find.byKey(const Key('logger.switch')));
      await tester.pumpAndSettle();
      await choose(tester, boxSquat);
      await tester.pumpAndSettle();

      final snackBar = find.byType(SnackBar);
      expect(snackBar, findsOneWidget);
      expect(find.text('Swapped to Box squat'), findsOneWidget);
      final primary = find.byKey(const Key('logger.primary'));
      // The bar's own surface: the SnackBar widget's box also spans the
      // margin below it, which is see-through and lets taps pass.
      final bar = find
          .descendant(of: snackBar, matching: find.byType(Material))
          .first;
      expect(
        tester.getRect(bar).overlaps(tester.getRect(primary)),
        isFalse,
        reason: 'Start logging is the very next tap after a switch',
      );

      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('logger.demo')), findsNothing);
      expect(find.byKey(const Key('set.1.weight')), findsOneWidget);
    });
  });
}
