import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart' show exerciseDetailProvider;
import 'package:fitsync/features/plans/domain/workout_plan.dart';
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

ActiveSession _session({List<LoggedSet> sets = const []}) => ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      sets: sets,
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
}) async {
  final controller = FakeSessionController(session ?? _session());

  await tester.pumpWidget(ProviderScope(
    overrides: [
      activePlanProvider.overrideWith((ref) async => _plan),
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

void main() {
  testWidgets('lists every exercise in the plan with the first expanded', (tester) async {
    await _pump(tester);

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Push-up'), findsOneWidget);
    // The first card opens on arrival; the second stays collapsed.
    expect(find.byKey(const Key('set.1.weight')), findsOneWidget);
  });

  testWidgets('progress counts sets across the whole session', (tester) async {
    await _pump(tester, session: _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
    ]));

    // 3 target sets + 2 target sets = 5.
    expect(find.text('1 of 5 sets'), findsOneWidget);
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

  testWidgets('tapping a collapsed card expands it and collapses the other', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('logcard.102')));
    await tester.pumpAndSettle();

    // Push-up has 2 target sets; a third row would mean the squat is still open.
    expect(find.byKey(const Key('set.3.weight')), findsNothing);
    expect(find.byKey(const Key('set.2.weight')), findsOneWidget);
  });

  // Beyond the brief -- the card and the pushed screen are each tested in
  // isolation, but nothing exercised the glue in session_logger_screen.dart
  // that turns a card's list index into the pushed screen's position/total.
  // Using the SECOND card specifically: an off-by-one that passed `index`
  // instead of `index + 1` would show "Exercise 1 of 2" here too, the same
  // text a correct first-card tap would produce -- so only the second card
  // can tell the two apart.
  testWidgets('opening the demo from the second card shows its real position',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('logcard.demo.102')));
    await tester.pumpAndSettle();

    expect(find.text('Exercise 2 of 2'), findsOneWidget);
    expect(find.text('2 × 10-15'), findsOneWidget);
  });

  testWidgets('finishing sends the elapsed minutes and shows a summary', (tester) async {
    final controller = await _pump(tester, session: _session(sets: const [
      LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 10),
    ]));

    await tester.tap(find.byKey(const Key('logger.finish')));
    await tester.pumpAndSettle();

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

    await tester.tap(find.byKey(const Key('logger.finish')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('logger.summary')), findsNothing);
    // Gone from the stack, not merely summary-less: the host route is back.
    expect(find.byKey(const Key('logger.finish')), findsNothing);
    expect(find.text('open logger'), findsOneWidget);
    expect(find.text('This session was already finished.'), findsOneWidget);
  });

  testWidgets('discarding asks first, then abandons', (tester) async {
    final controller = await _pump(tester);

    await tester.tap(find.byKey(const Key('logger.discard')));
    await tester.pumpAndSettle();
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

    await tester.tap(find.byKey(const Key('logger.finish')));
    await tester.tap(find.byKey(const Key('logger.finish')));
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

    await tester.tap(find.byKey(const Key('logger.finish')));
    await tester.pumpAndSettle();

    expect(find.text('This session was already finished.'), findsOneWidget);
    expect(find.text('Something went wrong.'), findsNothing);
    expect(find.byKey(const Key('logger.summary')), findsNothing);
    expect(find.byKey(const Key('logger.finish')), findsNothing);
    expect(find.text('open logger'), findsOneWidget);
  });

  // The same contract on the Discard side: abandon() reads _current too.
  testWidgets('a StateError from abandon leaves by the already-finished path',
      (tester) async {
    final controller = await _pump(tester);
    controller.abandonError = StateError('No session is in progress.');

    await tester.tap(find.byKey(const Key('logger.discard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(controller.calls, contains('abandon'));
    expect(find.text('This session was already finished.'), findsOneWidget);
    expect(find.byKey(const Key('logger.finish')), findsNothing);
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

      await tester.tap(find.byKey(const Key('logger.finish')));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      // Not closed, not summarised, and above all not navigated away from:
      // the logger is still the route on top and the session is in progress.
      expect(find.byKey(const Key('logger.finish')), findsOneWidget);
      expect(find.byKey(const Key('logger.summary')), findsNothing);
      expect(controller.heldSession, isNotNull);
      expect(tester.takeException(), isNull);

      // Resumable in practice, not just in state: the _finishing guard was
      // released, so a second attempt actually reaches the controller. A
      // guard left stuck would leave a session that can never be finished
      // from here. The SnackBar has to clear first -- it sits at the bottom
      // of the Scaffold over the Finish button and would swallow the tap.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logger.finish')));
      await tester.pumpAndSettle();
      expect(controller.calls.where((c) => c.startsWith('complete:')).length, 2);
    });
  }

  // Beyond the brief -- Discard is destructive and its request can simply
  // fail. Without a handler the future's error is unhandled, the screen does
  // not move, and the tap reads as though it did nothing at all.
  testWidgets('a discard that fails says so and keeps the session', (tester) async {
    final controller = await _pump(tester);
    controller.abandonError = const ApiException('NETWORK', 'No connection.');

    await tester.tap(find.byKey(const Key('logger.discard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('No connection.'), findsOneWidget);
    // Still on the logger, still logging: nothing was thrown away.
    expect(find.byKey(const Key('logger.finish')), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('logger.discard')));
    await tester.pumpAndSettle();
    expect(find.text('Discard this session?'), findsOneWidget);

    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();

    expect(controller.calls, isNot(contains('abandon')));
    expect(find.text('Discard this session?'), findsNothing);
    expect(find.byKey(const Key('logger.finish')), findsOneWidget);
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
    expect(find.byKey(const Key('logger.finish')), findsNothing);
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
    expect(find.byKey(const Key('logger.finish')), findsNothing);
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

    // The header must not read "-90 min" either.
    expect(find.text('0 min'), findsOneWidget);

    await tester.tap(find.byKey(const Key('logger.finish')));
    await tester.pumpAndSettle();

    expect(controller.calls, contains('complete:0'));
    expect(find.byKey(const Key('logger.summary')), findsOneWidget);
  });
}
