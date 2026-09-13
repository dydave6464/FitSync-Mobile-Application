import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_filters.dart';
import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_logger_screen.dart';

class FakeExerciseRepository implements ExerciseRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<ExercisePage> list({
    String? muscleGroup,
    String? equipment,
    int page = 1,
    int limit = 20,
  }) async =>
      ExercisePage(
        items: const [
          ExerciseSummary(
            exerciseId: 101, name: 'Goblet squat', muscleGroup: 'quadriceps',
            equipment: 'Dumbbell', thumbnailUrl: null,
          ),
          ExerciseSummary(
            exerciseId: 202, name: 'Cable fly', muscleGroup: 'pectorals',
            equipment: 'Cable', thumbnailUrl: null,
          ),
        ],
        page: page,
        limit: limit,
        total: 2,
      );

  @override
  Future<ExerciseFilters> filters() async =>
      const ExerciseFilters(
        muscleGroups: [FilterOption(value: 'quadriceps', count: 1)],
        equipment: [FilterOption(value: 'Dumbbell', count: 1)],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Records what the picker asked the server to start.
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
      sessionDate: '2026-09-13',
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

Future<void> _pump(
  WidgetTester tester, {
  bool selecting = true,
  FakeSessionRepository? sessions,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      exerciseRepositoryProvider.overrideWithValue(FakeExerciseRepository()),
      sessionRepositoryProvider
          .overrideWithValue(sessions ?? FakeSessionRepository()),
      // A manual session has none; the logger must not need one.
      activePlanProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      theme: fsLightTheme(),
      home: ExerciseListScreen(selecting: selecting),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _start() => find.byKey(const Key('picker.start'));

void main() {
  testWidgets('browsing offers nothing to start', (tester) async {
    // The Browse tab is the same screen. A footer there would offer to start
    // a workout from a list nobody is picking from.
    await _pump(tester, selecting: false);

    expect(_start(), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
  });

  testWidgets('picking offers a start button, inert until something is chosen',
      (tester) async {
    await _pump(tester);

    expect(_start(), findsOneWidget);
    expect(tester.widget<FsButton>(_start()).onPressed, isNull,
        reason: 'a workout of no exercises is not a workout');
  });

  testWidgets('tapping a row adds it and the count follows', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 added'), findsOneWidget);
    expect(tester.widget<FsButton>(_start()).onPressed, isNotNull);
  });

  testWidgets('tapping a chosen row takes it back out', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 added'), findsNothing);
    expect(tester.widget<FsButton>(_start()).onPressed, isNull);
  });

  testWidgets('starting sends the exercises in the order they were picked',
      (tester) async {
    final sessions = FakeSessionRepository();
    await _pump(tester, sessions: sessions);

    await tester.tap(find.text('Cable fly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();
    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(sessions.startedWith, [202, 101]);
  });

  testWidgets('starting opens the logger on the new session', (tester) async {
    final sessions = FakeSessionRepository();
    await _pump(tester, sessions: sessions);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();
    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  testWidgets('a workout already in progress is named, not silently resumed',
      (tester) async {
    // The server is idempotent here: it returns the running session and
    // ignores the list. Pushing the logger regardless would drop everything
    // the user just picked and open a workout they did not choose.
    final sessions = FakeSessionRepository(
      existing: ActiveSession(
        sessionId: 3, status: 'in_progress', sessionDate: '2026-09-13',
        startedAt: DateTime.now(),
      ),
    );
    await _pump(tester, sessions: sessions);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();
    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.textContaining('already'), findsOneWidget);
    expect(sessions.startCalls, 0, reason: 'nothing should have been started');
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });

  testWidgets('a failed start keeps the picks so they can be retried',
      (tester) async {
    final sessions = FakeSessionRepository(
      error: const ApiException('SERVER_ERROR', 'Could not start that.'),
    );
    await _pump(tester, sessions: sessions);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();
    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not start that'), findsOneWidget);
    expect(find.textContaining('1 added'), findsOneWidget);
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });
}
