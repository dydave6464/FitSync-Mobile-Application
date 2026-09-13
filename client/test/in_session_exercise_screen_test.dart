import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_filters.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/presentation/in_session_exercise_screen.dart';

const _exercise = PlanExercise(
  planExerciseId: 601, exerciseId: 101, name: 'Goblet squat',
  muscleGroup: 'quadriceps', orderNo: 1, targetSets: 4, targetReps: '8-10',
);

const _detail = ExerciseDetail(
  exerciseId: 101,
  name: 'Goblet squat',
  muscleGroup: 'quadriceps',
  equipment: 'dumbbell',
  thumbnailUrl: null,
  animationUrl: null,
  cues: ['Sit between your hips', 'Keep your chest tall'],
);

/// The same exercise as the catalogue actually stores it: `animationUrl` is a
/// server-relative `/storage/...` key, meaningless without the API base URL.
const _detailWithAnimation = ExerciseDetail(
  exerciseId: 101,
  name: 'Goblet squat',
  muscleGroup: 'quadriceps',
  equipment: 'dumbbell',
  thumbnailUrl: null,
  animationUrl: '/storage/exercises/0101/animation.gif',
  cues: ['Sit between your hips'],
);

/// Only [baseUrl] matters here -- the detail itself is injected through
/// [exerciseDetailProvider], so no fetch ever reaches this.
class _BaseUrlRepository implements ExerciseRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<ExercisePage> list({
    List<String> muscleGroups = const [], String? equipment, int page = 1, int limit = 20,
  }) async => throw UnimplementedError();

  @override
  Future<ExerciseDetail> byId(int id) async => throw UnimplementedError();

  @override
  Future<ExerciseFilters> filters() async => throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, {ExerciseDetail detail = _detail}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      exerciseRepositoryProvider.overrideWithValue(_BaseUrlRepository()),
      exerciseDetailProvider.overrideWith((ref, id) async => detail),
    ],
    child: MaterialApp(
      theme: fsLightTheme(),
      home: const InSessionExerciseScreen(
        exercise: _exercise, position: 1, total: 6,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the position, the prescription and the seeded cues', (tester) async {
    await _pump(tester);

    expect(find.text('Exercise 1 of 6'), findsOneWidget);
    expect(find.text('4 × 8-10'), findsOneWidget);
    expect(find.text('Goblet squat'), findsWidgets);
    expect(find.textContaining('Sit between your hips'), findsOneWidget);
    expect(find.textContaining('Keep your chest tall'), findsOneWidget);
  });

  testWidgets('Done returns to the logger', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('insession.done')), findsOneWidget);
    await tester.tap(find.byKey(const Key('insession.done')));
    await tester.pumpAndSettle();

    // Popped the only route, so the screen is gone.
    expect(find.text('Exercise 1 of 6'), findsNothing);
  });

  // --- Addition beyond the brief's list ---

  testWidgets(
      'a failed fetch says logging still works, and Done is still there',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        exerciseRepositoryProvider.overrideWithValue(_BaseUrlRepository()),
        exerciseDetailProvider.overrideWith(
          (ref, id) async => throw Exception('offline'),
        ),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: const InSessionExerciseScreen(
          exercise: _exercise, position: 1, total: 6,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not load this exercise. You can still log your sets.'),
      findsOneWidget,
    );
    // The position/prescription header lives inside the data branch, so a
    // failed fetch must not show stale or fabricated prescription text.
    expect(find.text('Exercise 1 of 6'), findsNothing);
    expect(find.text('4 × 8-10'), findsNothing);

    expect(find.byKey(const Key('insession.done')), findsOneWidget);
    await tester.tap(find.byKey(const Key('insession.done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insession.done')), findsNothing);
  });

  testWidgets('the demo image is built against the API base URL', (tester) async {
    // The whole reason this screen exists mid-workout. animationUrl is a
    // server-relative '/storage/...' key, so without the base URL the widget
    // requests "null/storage/..." and silently falls through to the equipment
    // icon -- a plausible-looking placeholder where the demo should be.
    await _pump(tester, detail: _detailWithAnimation);

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      'http://test.local/storage/exercises/0101/animation.gif',
    );
  });
}
