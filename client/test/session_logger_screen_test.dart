import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart' show exerciseDetailProvider;
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_logger_screen.dart';

const _plan = WorkoutPlan(
  planId: 42,
  name: 'Week 1 — Full body',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [
    PlanExercise(
      planExerciseId: 601, exerciseId: 101, name: 'Goblet squat',
      muscleGroup: 'quadriceps', orderNo: 1, targetSets: 3, targetReps: '8-12',
    ),
    PlanExercise(
      planExerciseId: 602, exerciseId: 102, name: 'Push-up',
      muscleGroup: 'chest', orderNo: 2, targetSets: 2, targetReps: '10-15',
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
      planExerciseId: 601, exerciseId: 101, name: 'Goblet squat',
      muscleGroup: 'quadriceps', orderNo: 1, targetSets: 3, targetReps: '8-12',
      dayNo: 1,
    ),
    PlanExercise(
      planExerciseId: 602, exerciseId: 102, name: 'Push-up',
      muscleGroup: 'chest', orderNo: 2, targetSets: 2, targetReps: '10-15',
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

  /// When set, [complete] suspends here before doing anything else -- lets a
  /// test dispatch a second Finish tap while the first is still in flight,
  /// the way two rapid taps would race a real network round trip. Null (the
  /// default) resolves immediately, matching every test that isn't exercising
  /// that race.
  Completer<void>? completeGate;

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
    if (logSetError != null) throw logSetError!;
    state = AsyncValue.data(
      state.value!.withSet(LoggedSet(
        exerciseId: exerciseId, setNumber: setNumber, weightKg: weightKg, reps: reps,
      )),
    );
  }

  @override
  Future<void> unlogSet({required int exerciseId, required int setNumber}) async {
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
    final done = ActiveSession(
      sessionId: 7, status: 'completed', sessionDate: '2026-09-08',
      durationMin: durationMin, totalVolumeKg: 380,
      sets: state.value!.sets,
    );
    state = const AsyncValue.data(null);
    return done;
  }

  @override
  Future<void> abandon() async {
    calls.add('abandon');
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

ActiveSession _session({List<LoggedSet> sets = const [], int? planDayNo}) => ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      sets: sets,
      planDayNo: planDayNo,
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
  WorkoutPlan plan = _plan,
}) async {
  final controller = FakeSessionController(session ?? _session());

  await tester.pumpWidget(ProviderScope(
    overrides: [
      activePlanProvider.overrideWith((ref) async => plan),
      profileProvider.overrideWith(() => FakeProfileNotifier(unit, patches ?? [])),
      activeSessionProvider.overrideWith(() => controller),
      lastPerformanceProvider.overrideWith((ref, key) async => const {}),
      // Only exercised by the demo-affordance navigation test below; every
      // other test here never opens the pushed screen, so this override is
      // inert for them.
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
  ));
  await tester.tap(find.text('open logger'));
  await tester.pumpAndSettle();
  return controller;
}

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
  testWidgets('shows one exercise at a time, not the whole plan', (tester) async {
    await _pump(tester);

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Push-up'), findsNothing);
  });

  testWidgets('the footer advances to the next exercise', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(find.text('Push-up'), findsOneWidget);
    expect(find.text('Goblet squat'), findsNothing);
  });

  testWidgets('the header names the position in the workout', (tester) async {
    await _pump(tester);
    expect(find.textContaining('Exercise 1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Exercise 2 / 2'), findsOneWidget);
  });

  testWidgets(
      'the position counter opens a sheet listing every exercise with its progress',
      (tester) async {
    await _pump(tester, session: _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
    ]));

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
        matching: find.text('1/3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('jump.102')),
        matching: find.text('0/2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('choosing an exercise from the sheet goes straight to it',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('logger.position')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('jump.102')));
    await tester.pumpAndSettle();

    // Both, deliberately: the counter alone would pass if the sheet moved the
    // index without the body following, and the name alone would pass if the
    // body moved without the header.
    expect(find.textContaining('Exercise 2 / 2'), findsOneWidget);
    expect(find.text('Push-up'), findsOneWidget);
  });

  testWidgets('back steps to the previous exercise before leaving the logger',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Exercise 2 / 2'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.textContaining('Exercise 1 / 2'), findsOneWidget);
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

  testWidgets('the summary reports the volume in the chosen unit',
      (tester) async {
    await _pump(tester, unit: WeightUnit.lb, session: _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
    ]));

    await _menu(tester, 'finish');

    // The closed session comes back at 380 kg, which is 837.75... lb.
    expect(find.textContaining('838 lb lifted'), findsOneWidget);
  });

  testWidgets('switching the unit in the header saves it to the profile',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pump(tester, patches: patches);

    await tester.tap(find.byKey(const Key('unit.lb')));
    await tester.pumpAndSettle();

    expect(patches, [
      {'weightUnit': 'lb'},
    ]);
  });

  testWidgets('progress counts sets across the whole session', (tester) async {
    await _pump(tester, session: _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
    ]));

    // 3 target sets + 2 target sets = 5. Asserted through semantics because
    // the mockup's meta row shows only the bar -- a screen reader still has
    // to be able to get the number out of it.
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('1 of 5 sets'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('ticking a set reaches the controller and starts the rest timer', (tester) async {
    final controller = await _pump(tester);

    await tester.enterText(find.byKey(const Key('set.1.weight')), '25');
    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(controller.calls, contains('log:101:1:25.0:8'));
    expect(find.byKey(const Key('rest.remaining')), findsOneWidget);
  });

  testWidgets('a failed write shows a retry and no rest timer', (tester) async {
    final controller = await _pump(tester);
    controller.logSetError = Exception('offline');

    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(const Key('rest.remaining')), findsNothing);
  });

  // Beyond the brief -- the panel and the pushed screen are each tested in
  // isolation, but nothing exercised the glue in session_logger_screen.dart
  // that turns the exercise on screen into the pushed screen's position and
  // total. Advancing to the SECOND exercise first is what makes it bite: an
  // off-by-one passing `index` instead of `index + 1` would read
  // "Exercise 1 of 2" here, the same text a correct first-exercise tap
  // produces -- so only the second exercise tells the two apart.
  testWidgets('opening the demo shows the exercise on screen, not the first',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logpanel.demo.102')));
    await tester.pumpAndSettle();

    expect(find.text('Exercise 2 of 2'), findsOneWidget);
    expect(find.text('2 × 10-15'), findsOneWidget);
  });

  testWidgets('finishing sends the elapsed minutes and shows a summary', (tester) async {
    final controller = await _pump(tester, session: _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
    ]));

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

  testWidgets('a session closed elsewhere pops the logger instead of hanging', (tester) async {
    final controller = await _pump(tester);
    controller.completeError = const ApiException(
      'SESSION_NOT_IN_PROGRESS', 'This session has already been closed.',
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
    final controller = await _pump(tester, session: _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
    ]));
    final gate = Completer<void>();
    controller.completeGate = gate;

    await _menu(tester, 'finish');
    await _menu(tester, 'finish');
    gate.complete();
    await tester.pumpAndSettle();

    expect(controller.calls.where((call) => call.startsWith('complete:')).length, 1);
    // No raw StateError (or anything else) escaped unhandled.
    expect(tester.takeException(), isNull);
  });

  // Beyond the brief -- carried issue (a) again, at the point where it
  // actually surfaces. The _finishing guard above stops a SECOND tap from
  // reaching the controller, so it never exercises the catch itself. This
  // does: the controller rejects the completion outright with the raw
  // StateError its _current getter throws. That must land on the same path
  // as the 409 -- pop with the plain-language message -- and never fall
  // through to the generic handler, which would leave the user standing on
  // a dead session reading "Something went wrong."
  testWidgets('a StateError from complete leaves by the already-finished path',
      (tester) async {
    final controller = await _pump(tester);
    controller.completeError = StateError('No session is in progress.');

    await _menu(tester, 'finish');

    expect(find.text('This session was already finished.'), findsOneWidget);
    expect(find.text('Something went wrong.'), findsNothing);
    expect(find.byKey(const Key('logger.summary')), findsNothing);
    expect(find.byType(SessionLoggerScreen), findsNothing);
    expect(find.text('open logger'), findsOneWidget);
  });

  // The same contract on the Discard side: abandon() reads _current too.
  testWidgets('a StateError from abandon leaves by the already-finished path',
      (tester) async {
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
    ('a named API failure', const ApiException('NETWORK', 'No connection.'),
        'No connection.'),
    ('an unnamed failure', Exception('offline'), 'Something went wrong.'),
  ]) {
    testWidgets('a finish that fails with $kind leaves the session in progress',
        (tester) async {
      final controller = await _pump(tester, session: _session(sets: const [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
      ]));
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
      expect(controller.calls.where((c) => c.startsWith('complete:')).length, 2);
    });
  }

  // Beyond the brief -- Discard is destructive and its request can simply
  // fail. Without a handler the future's error is unhandled, the screen does
  // not move, and the tap reads as though it did nothing at all.
  testWidgets('a discard that fails says so and keeps the session', (tester) async {
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
  // that write throw the raw StateError. The set must fall back to the same
  // retry affordance as any other failed write -- and, because the write did
  // not store anything, must not start a rest countdown.
  testWidgets('a set write the controller rejects mid-flight offers a retry',
      (tester) async {
    final controller = await _pump(tester);
    controller.logSetError = StateError('No session is in progress.');

    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(const Key('rest.remaining')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Beyond the brief -- the brief's own test list only ever confirms
  // Discard. Cancelling via "Keep going" must leave the session alone and
  // the logger on screen.
  testWidgets('cancelling discard leaves the logger open without abandoning', (tester) async {
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
  // closes the logger and refetches. That was wired for Finish and Discard but
  // not for the set writes, where SetRow's blanket catch turned the 409 into an
  // inline Retry that can never succeed: a session closed on another device
  // left the user tapping Retry forever.
  testWidgets('a 409 on a set write closes the logger instead of offering a dead retry',
      (tester) async {
    final controller = await _pump(tester);
    controller.logSetError = const ApiException(
      'SESSION_NOT_IN_PROGRESS', 'This session has already been closed.',
    );

    await tester.enterText(find.byKey(const Key('set.1.reps')), '8');
    await tester.tap(find.byKey(const Key('set.1.tick')));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing);
    expect(find.byType(SessionLoggerScreen), findsNothing);
    expect(find.text('open logger'), findsOneWidget);
    expect(find.text('This session was already finished.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 409 on an undo closes the logger too', (tester) async {
    final controller = await _pump(tester, session: _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
    ]));
    controller.unlogSetError = const ApiException(
      'SESSION_NOT_IN_PROGRESS', 'This session has already been closed.',
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
  testWidgets('a clock behind the server still finishes, at zero minutes',
      (tester) async {
    final controller = await _pump(tester, session: ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      startedAt: DateTime.now().add(const Duration(minutes: 90)),
    ));

    // The header must not read "-90 min elapsed" either.
    expect(find.text('0 min elapsed'), findsOneWidget);

    await _menu(tester, 'finish');

    expect(controller.calls, contains('complete:0'));
    expect(find.byKey(const Key('logger.summary')), findsOneWidget);
  });

  // The logger reads the whole plan today. With a rotation it must show only
  // the day the session is on, or a Push session lists the Pull exercises too.
  testWidgets('the logger shows only the session day, not the whole plan',
      (tester) async {
    await _pump(tester, plan: _rotationPlan, session: _session(planDayNo: 2));

    expect(find.textContaining('Push-up'), findsOneWidget);
    expect(find.text('Goblet squat'), findsNothing);
    expect(find.textContaining('Exercise 1 / 1'), findsOneWidget);
  });
}
