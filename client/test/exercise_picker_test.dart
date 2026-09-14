import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:fitsync/features/sessions/presentation/workout_review_screen.dart';

class FakeExerciseRepository implements ExerciseRepository {
  List<String>? asked;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<ExercisePage> list({
    List<String> muscleGroups = const [],
    String? equipment,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    asked = muscleGroups;
    return ExercisePage(
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
  }

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
  FakeExerciseRepository? exercises,
  List<String> muscleGroups = const [],
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      exerciseRepositoryProvider
          .overrideWithValue(exercises ?? FakeExerciseRepository()),
      if (muscleGroups.isNotEmpty)
        catalogueConstraintProvider.overrideWith(
          () => _ConstrainedTo(muscleGroups),
        ),
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

/// The catalogue narrowed to a training day, as the setup screen leaves it.
class _ConstrainedTo extends CatalogueConstraintNotifier {
  _ConstrainedTo(this.groups);

  final List<String> groups;

  @override
  List<String> build() => groups;
}

Finder _review() => find.byKey(const Key('picker.review'));

void main() {
  testWidgets('browsing offers nothing to start', (tester) async {
    // The Browse tab is the same screen. A footer there would offer to start
    // a workout from a list nobody is picking from.
    await _pump(tester, selecting: false);

    expect(_review(), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
  });

  testWidgets('picking offers a review button, inert until something is chosen',
      (tester) async {
    await _pump(tester);

    expect(_review(), findsOneWidget);
    expect(tester.widget<FsButton>(_review()).onPressed, isNull,
        reason: 'a workout of no exercises is not a workout');
  });

  testWidgets('tapping a row adds it and the count follows', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 added'), findsOneWidget);
    expect(tester.widget<FsButton>(_review()).onPressed, isNotNull);
  });

  testWidgets('tapping a chosen row takes it back out', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 added'), findsNothing);
    expect(tester.widget<FsButton>(_review()).onPressed, isNull);
  });

  testWidgets('the footer leads to the review screen, not straight to a session',
      (tester) async {
    // Starting from here meant the picks were only ever reviewable as ticks
    // scattered down a 1,200-row catalogue. The library hands off now.
    final sessions = FakeSessionRepository();
    await _pump(tester, sessions: sessions);

    await tester.tap(find.text('Cable fly'));
    await tester.pumpAndSettle();
    await tester.tap(_review());
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutReviewScreen), findsOneWidget);
    expect(sessions.startCalls, 0, reason: 'reviewing is not starting');
  });

  testWidgets('the review screen shows the picks in the order they were made',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Cable fly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();
    await tester.tap(_review());
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Cable fly')).dy,
      lessThan(tester.getTopLeft(find.text('Goblet squat')).dy),
    );
  });

  testWidgets('adding more from the review screen lands back on the library',
      (tester) async {
    // Popping rather than pushing: a second library would leave two of them
    // on the stack and two ways back.
    await _pump(tester);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();
    await tester.tap(_review());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review.addMore')));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutReviewScreen), findsNothing);
    expect(find.text('Cable fly'), findsOneWidget, reason: 'back on the library');
    expect(find.textContaining('1 added'), findsOneWidget,
        reason: 'the picks survived the round trip');
  });

  testWidgets("the training day's groups are what the catalogue is asked for",
      (tester) async {
    // The day chosen on the setup screen has to reach the request, or the
    // library shows all 1,203 exercises under a heading that says Push.
    final exercises = FakeExerciseRepository();

    await _pump(tester, exercises: exercises,
        muscleGroups: const ['pectorals', 'delts', 'triceps']);

    expect(exercises.asked, ['pectorals', 'delts', 'triceps']);
  });

  testWidgets('browsing asks for the whole catalogue', (tester) async {
    final exercises = FakeExerciseRepository();

    await _pump(tester, selecting: false, exercises: exercises);

    expect(exercises.asked, isEmpty);
  });
}
