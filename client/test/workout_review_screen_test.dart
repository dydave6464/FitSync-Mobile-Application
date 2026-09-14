import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_logger_screen.dart';
import 'package:fitsync/features/sessions/presentation/workout_draft.dart';
import 'package:fitsync/features/sessions/presentation/workout_review_screen.dart';

const _squat = ExerciseSummary(
  exerciseId: 101, name: 'Goblet squat', muscleGroup: 'quadriceps',
  equipment: 'dumbbell', thumbnailUrl: null,
);
const _fly = ExerciseSummary(
  exerciseId: 202, name: 'Cable fly', muscleGroup: 'pectorals',
  equipment: 'cable', thumbnailUrl: null,
);
const _press = ExerciseSummary(
  exerciseId: 303, name: 'Bench press', muscleGroup: 'pectorals',
  equipment: 'barbell', thumbnailUrl: null,
);

class FakeExerciseRepository implements ExerciseRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Records what the review screen asked the server to start.
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({this.error, this.existing});

  final Object? error;

  /// A session already in progress, as `GET /sessions/active` would report.
  final ActiveSession? existing;

  List<int>? startedWith;
  int startCalls = 0;

  @override
  Future<ActiveSession?> active() async => existing;

  @override
  Future<ActiveSession> start({List<int>? exerciseIds}) async {
    startCalls += 1;
    startedWith = exerciseIds;
    if (error != null) throw error!;
    return ActiveSession(
      sessionId: 9,
      status: 'in_progress',
      sessionDate: '2026-09-14',
      startedAt: DateTime.now(),
      exercises: [
        for (final (index, id) in (exerciseIds ?? const <int>[]).indexed)
          PlanExercise(
            planExerciseId: index + 1, exerciseId: id, name: 'Ex $id',
            muscleGroup: 'x', orderNo: index + 1, targetSets: 3,
            targetReps: '8-12',
          ),
      ],
    );
  }

  @override
  Future<Map<int, LastPerformance>> lastPerformance(List<int> ids) async => const {};

  @override
  Future<Set<String>> completedThisWeek() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Seeds the draft the library would have filled in.
class _Picked extends WorkoutDraftNotifier {
  _Picked(this.picks);
  final List<ExerciseSummary> picks;

  @override
  List<ExerciseSummary> build() => picks;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<ExerciseSummary> picks,
  FakeSessionRepository? sessions,
}) async {
  final container = ProviderContainer(overrides: [
    exerciseRepositoryProvider.overrideWithValue(FakeExerciseRepository()),
    sessionRepositoryProvider
        .overrideWithValue(sessions ?? FakeSessionRepository()),
    workoutDraftProvider.overrideWith(() => _Picked(picks)),
    // A manual session has no plan; the logger must not need one.
    activePlanProvider.overrideWith((ref) async => null),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: fsLightTheme(),
      home: const WorkoutReviewScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

Finder _start() => find.byKey(const Key('review.start'));

/// Drags the row's handle onto [target]'s position and drops it there.
///
/// A single `tester.drag` is one synthetic move, which ReorderableListView
/// does not treat as a reorder -- it tracks the pointer across frames to work
/// out which slot the row is over. Stepping the gesture and pumping between
/// moves is what a real finger looks like to it.
Future<void> _dragOnto(
  WidgetTester tester,
  Key handle,
  Key target,
) async {
  final from = tester.getCenter(find.byKey(handle));
  final to = tester.getCenter(find.byKey(target));

  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 16));

  // The first move has to clear kTouchSlop or the drag is never recognised,
  // so the step size is chosen to exceed it rather than by splitting the
  // distance into a fixed number of parts.
  final total = to - from;
  final steps = (total.distance / (kTouchSlop * 2)).ceil().clamp(2, 40);
  final step = total / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }

  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the picks in the order they will be trained',
      (tester) async {
    await _pump(tester, picks: const [_squat, _fly, _press]);

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Cable fly'), findsOneWidget);
    expect(find.text('Bench press'), findsOneWidget);

    // Top-to-bottom on screen is the order the logger walks, so the screen
    // has to render it in that order rather than in id or name order.
    final positions = [
      tester.getTopLeft(find.text('Goblet squat')).dy,
      tester.getTopLeft(find.text('Cable fly')).dy,
      tester.getTopLeft(find.text('Bench press')).dy,
    ];
    expect(positions, orderedEquals([...positions]..sort()));
  });

  testWidgets('says how many exercises the workout holds', (tester) async {
    await _pump(tester, picks: const [_squat, _fly]);

    expect(find.textContaining('2 exercises'), findsOneWidget);
  });

  testWidgets('one exercise is not called "1 exercises"', (tester) async {
    await _pump(tester, picks: const [_squat]);

    expect(find.textContaining('1 exercise'), findsOneWidget);
    expect(find.textContaining('1 exercises'), findsNothing);
  });

  testWidgets('removing a row drops it from the workout', (tester) async {
    final container = await _pump(tester, picks: const [_squat, _fly]);

    await tester.tap(find.byKey(const Key('review.remove.101')));
    await tester.pumpAndSettle();

    expect(find.text('Goblet squat'), findsNothing);
    expect(container.read(workoutDraftProvider).exerciseIds, [202]);
  });

  testWidgets('starting sends the ids in the order shown', (tester) async {
    final sessions = FakeSessionRepository();
    await _pump(tester, picks: const [_squat, _fly, _press], sessions: sessions);

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(sessions.startedWith, [101, 202, 303]);
  });

  testWidgets('dragging an exercise to the top starts it first',
      (tester) async {
    // The whole reason the screen is draggable: order_no comes from this, and
    // before the drag the order was only "whichever row was tapped first".
    final sessions = FakeSessionRepository();
    await _pump(tester, picks: const [_squat, _fly, _press], sessions: sessions);

    await _dragOnto(
      tester,
      const Key('review.drag.303'),
      const Key('review.drag.101'),
    );

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(sessions.startedWith!.first, 303,
        reason: 'the dragged exercise must be trained first');
  });

  testWidgets('starting opens the logger', (tester) async {
    await _pump(tester, picks: const [_squat]);

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  testWidgets('a started workout leaves nothing drafted', (tester) async {
    final container = await _pump(tester, picks: const [_squat]);

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(container.read(workoutDraftProvider), isEmpty);
  });

  testWidgets('a failed start keeps the picks so they can be retried',
      (tester) async {
    final sessions = FakeSessionRepository(
      error: const ApiException('NETWORK_ERROR', 'Could not reach the server.'),
    );
    final container =
        await _pump(tester, picks: const [_squat, _fly], sessions: sessions);

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the server.'), findsOneWidget);
    expect(container.read(workoutDraftProvider).exerciseIds, [101, 202],
        reason: 'choosing them all again is not a retry');
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });

  testWidgets('a workout already in progress is reported, not replaced',
      (tester) async {
    // The server is idempotent here: it returns the running session and
    // ignores the list, so opening the logger anyway would drop everything
    // just picked and show a workout the user did not choose.
    final sessions = FakeSessionRepository(
      existing: ActiveSession(
        sessionId: 4,
        status: 'in_progress',
        sessionDate: '2026-09-14',
        startedAt: DateTime.now(),
      ),
    );
    await _pump(tester, picks: const [_squat], sessions: sessions);

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.textContaining('already have a workout in progress'),
        findsOneWidget);
    expect(sessions.startCalls, 0);
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });

  testWidgets('an emptied workout cannot be started', (tester) async {
    await _pump(tester, picks: const [_squat]);

    await tester.tap(find.byKey(const Key('review.remove.101')));
    await tester.pumpAndSettle();

    expect(tester.widget<FsButton>(_start()).onPressed, isNull,
        reason: 'a workout of no exercises is not a workout');
  });
}
