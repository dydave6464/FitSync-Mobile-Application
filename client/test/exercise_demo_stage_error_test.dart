// The demo stage when the exercise will not load. exerciseDetailProvider is
// not autoDispose, so a failure is kept for the rest of the session: without
// a way to ask again, the demo stayed gone until the app restarted.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_cues.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_demo_stage.dart';

void main() {
  testWidgets('a failed load says so and can be tried again', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseDetailProvider.overrideWith((ref, id) async {
            if (loads++ == 0) {
              throw const ApiException('INVALID_RESPONSE', 'bad');
            }
            return const ExerciseDetail(
              exerciseId: 1,
              name: 'Barbell back squat',
              muscleGroup: 'quadriceps',
              equipment: 'barbell',
              thumbnailUrl: null,
              animationUrl: null,
              cues: ['Stand tall.'],
            );
          }),
          exerciseCuesProvider.overrideWith(
            (ref, id) async => const ExerciseCues(
              source: 'catalogue',
              injuryName: null,
              cues: [Cue(title: 'Stand tall.')],
            ),
          ),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: const Scaffold(
            body: ExerciseDemoStage(
              exercise: PlanExercise(
                planExerciseId: 1,
                exerciseId: 1,
                name: 'Barbell back squat',
                muscleGroup: 'quadriceps',
                orderNo: 1,
                targetSets: 3,
                targetReps: '8-12',
              ),
              positionLabel: 'Exercise 1 / 6',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Could not load this exercise. You can still log your sets.'),
      findsOneWidget,
    );
    expect(find.byType(FsRetry), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.byType(FsRetry), findsNothing);
    expect(find.textContaining('Stand tall.'), findsWidgets);
  });
}
