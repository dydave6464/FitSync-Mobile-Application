import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
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

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      exerciseDetailProvider.overrideWith((ref, id) async => _detail),
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
}
