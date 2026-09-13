import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_logger_screen.dart';
import 'package:fitsync/features/training/presentation/training_shell.dart';

const _plan = WorkoutPlan(
  planId: 42, name: 'Week 1 — Full body', splitStyle: 'full_body',
  daysPerWeek: 3, sessionLengthMin: 45, weekNo: 1,
  exercises: [
    PlanExercise(
      planExerciseId: 601, exerciseId: 101, name: 'Goblet squat',
      muscleGroup: 'quadriceps', orderNo: 1, targetSets: 3, targetReps: '8-12',
    ),
  ],
);

Future<void> _pump(WidgetTester tester, {ActiveSession? session}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      activePlanProvider.overrideWith((ref) async => _plan),
      activeSessionProvider.overrideWith(() => _StubController(session)),
      completedDaysProvider.overrideWith((ref) async => const <String>{}),
    ],
    child: MaterialApp(theme: fsLightTheme(), home: const TrainingShell()),
  ));
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
    state = const AsyncValue.data(ActiveSession(
      sessionId: 7, status: 'in_progress', sessionDate: '2026-09-08',
    ));
  }
}

Future<void> _pumpWithController(
  WidgetTester tester,
  ActiveSessionController Function() controller,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      activePlanProvider.overrideWith((ref) async => _plan),
      activeSessionProvider.overrideWith(controller),
      completedDaysProvider.overrideWith((ref) async => const <String>{}),
      // The logger this pushes into watches this too; without stubbing it,
      // the real repository would reach for a live ApiClient this test
      // never configured.
      lastPerformanceProvider.overrideWith((ref, key) async => const {}),
    ],
    child: MaterialApp(theme: fsLightTheme(), home: const TrainingShell()),
  ));
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

  testWidgets('Progress and Recovery say what is coming rather than nothing', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('tab.progress')));
    await tester.pumpAndSettle();
    expect(find.textContaining('once you have logged'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab.recovery')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recovery'), findsWidgets);
  });

  testWidgets('the Plan tab offers Start with no session', (tester) async {
    await _pump(tester);
    expect(find.text('Start session'), findsOneWidget);
  });

  testWidgets('the Plan tab offers Resume when one is in progress', (tester) async {
    await _pump(tester, session: const ActiveSession(
      sessionId: 7, status: 'in_progress', sessionDate: '2026-09-08',
    ));
    expect(find.text('Resume session'), findsOneWidget);
  });

  // Beyond the brief -- the four tests above only ever check which label the
  // button shows. None of them taps it, so none proves the button actually
  // reaches the controller or opens the logger.
  testWidgets('tapping Start calls start() and pushes the logger', (tester) async {
    final controller = _RecordingController();
    await _pumpWithController(tester, () => controller);

    expect(find.byType(SessionLoggerScreen), findsNothing,
        reason: 'the logger must not be open before Start is tapped');

    await tester.tap(find.byKey(const Key('session.start')));
    await tester.pumpAndSettle();

    expect(controller.startCalls, 1,
        reason: 'the button must reach the controller, not just relabel itself');
    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  // Beyond the brief -- a failed start (the realistic case: the user's plan
  // was deleted between render and tap, so the server refuses with
  // NO_ACTIVE_PLAN) must show the failure, must not open the logger on top
  // of a session that was never created, and must not strand the user on a
  // Plan tab whose only button is permanently disabled. `_starting` is
  // cleared in a `finally`; if it were not, the second tap below would never
  // reach the controller a second time.
  testWidgets('a failed start shows the message, does not push, and leaves Start usable',
      (tester) async {
    final controller = _RecordingController(
      startError: const ApiException('NO_ACTIVE_PLAN', 'Your plan was removed.'),
    );
    await _pumpWithController(tester, () => controller);

    await tester.tap(find.byKey(const Key('session.start')));
    await tester.pumpAndSettle();

    expect(find.text('Your plan was removed.'), findsOneWidget);
    expect(find.byType(SessionLoggerScreen), findsNothing);
    expect(controller.startCalls, 1);
    expect(find.text('Start session'), findsOneWidget,
        reason: 'a failed start must not have left the session as active');

    // Let the SnackBar clear -- it sits at the bottom of the Scaffold over
    // the button and would otherwise swallow the next tap, the same
    // precaution session_logger_screen_test.dart takes before a second
    // Finish tap.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session.start')));
    await tester.pumpAndSettle();

    expect(controller.startCalls, 2,
        reason: 'the button must still be wired up after a failed attempt, '
            'not stuck disabled by a _starting flag that was never reset');
    expect(tester.takeException(), isNull);
  });
}
