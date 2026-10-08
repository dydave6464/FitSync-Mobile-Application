import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_cues.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_demo_stage.dart';

/// What the catalogue answers for every exercise in this file -- its own
/// cues are what a failed or free-limited `/cues` call falls back to.
const _detail = ExerciseDetail(
  exerciseId: 1,
  name: 'Leg press',
  muscleGroup: 'quads',
  equipment: null,
  thumbnailUrl: null,
  animationUrl: null,
  cues: ['Stand tall.'],
);

// targetSets: 1 with no targetReps keeps the header's prescription text
// ("1 set") short. exercise_demo_stage.dart's header Row has no
// Flexible/Expanded around either Text, and on this 390pt surface widget
// tests render with a fallback font whose metrics are wider than the real
// SpaceGrotesk/JetBrainsMono faces (not loaded in flutter_test) -- a longer
// prescription like "3 sets x 8-12 reps" overflows the Row under that
// substitute font even though the production fonts fit it. Reproduced in
// isolation outside this file; fixing the header's robustness is outside
// this fix round's scope, so the workaround lives in the test's own data.
PlanExercise _exercise({Coaching? coaching}) => PlanExercise(
  planExerciseId: 1,
  exerciseId: 1,
  name: 'Leg press',
  muscleGroup: 'quads',
  orderNo: 1,
  targetSets: 1,
  targetReps: '',
  coaching: coaching,
);

/// Matches exercise_detail_screen_test.dart's `_usePortraitSurface`: the
/// default 800x600 test surface is wider than tall, which pushes content
/// below the demo's hero image out of the lazy-build window.
void _usePortraitSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpStage(
  WidgetTester tester, {
  required PlanExercise exercise,
  required Future<ExerciseCues> Function(int id) cues,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        exerciseDetailProvider.overrideWith((ref, id) async => _detail),
        exerciseCuesProvider.overrideWith((ref, id) => cues(id)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ExerciseDemoStage(
            exercise: exercise,
            positionLabel: 'Exercise 1 / 2',
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a coached exercise with an AI answer shows the coach panel', (
    tester,
  ) async {
    _usePortraitSurface(tester);
    await _pumpStage(
      tester,
      exercise: _exercise(coaching: (injuryId: 3, injuryName: 'Knee')),
      cues: (id) async => const ExerciseCues(
        source: 'ai',
        injuryName: 'Knee',
        cues: [Cue(title: 'Keep the knee soft.')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coach.panel')), findsOneWidget);
    expect(find.text('AI coaching for your knee'), findsOneWidget);
  });

  testWidgets(
    'the same exercise without coaching shows the plain AI cue list',
    (tester) async {
      _usePortraitSurface(tester);
      await _pumpStage(
        tester,
        exercise: _exercise(), // no coaching
        cues: (id) async => const ExerciseCues(
          source: 'ai',
          injuryName: 'Knee',
          cues: [Cue(title: 'Keep the knee soft.')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coach.panel')), findsNothing);
      // ai_cue_list.dart's own heading for an 'ai'-sourced answer -- the
      // path every exercise took before this branch, and still takes when
      // it carries no `coaching`.
      expect(find.text('AI coaching cues'), findsOneWidget);
    },
  );

  testWidgets(
    'an unavailable notice shows coach.unavailable, and retry refetches',
    (tester) async {
      _usePortraitSurface(tester);
      var fetches = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exerciseDetailProvider.overrideWith((ref, id) async => _detail),
            exerciseCuesProvider.overrideWith((ref, id) async {
              fetches++;
              return ExerciseCues.fromJson({
                'source': 'catalogue',
                'injury': {'injuryId': 3, 'name': 'Knee'},
                'notice': 'unavailable',
                'cues': [
                  {'title': 'Stand tall.'},
                ],
              });
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ExerciseDemoStage(
                exercise: _exercise(
                  coaching: (injuryId: 3, injuryName: 'Knee'),
                ),
                positionLabel: 'Exercise 1 / 2',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coach.unavailable')), findsOneWidget);
      expect(fetches, 1);

      await tester.tap(find.byKey(const Key('coach.retry')));
      // The retry invalidates exerciseCuesProvider for this exercise id,
      // which puts the panel back into its loading state -- the repeating
      // shimmer never settles, so pump explicit frames rather than
      // pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fetches, 2);
    },
  );
}
