// The demo stage's header: the position counter on the left, the target
// ("2 sets × 8-12 reps") on the right. The target is the line to keep whole --
// it is what the user is about to do -- so it is never cut to "…": with room it
// sits beside the counter, and without room it drops under it.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_cues.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_demo_stage.dart';

const _label = 'Exercise 1 / 6';
const _target = '2 sets × 8-12 reps';

Future<void> _pumpAtWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        exerciseDetailProvider.overrideWith(
          (ref, id) async => const ExerciseDetail(
            exerciseId: 1,
            name: 'Squat',
            muscleGroup: 'quads',
            equipment: null,
            thumbnailUrl: null,
            animationUrl: null,
            cues: ['Stand tall.'],
          ),
        ),
        exerciseCuesProvider.overrideWith(
          (ref, id) async => const ExerciseCues(
            source: 'catalogue',
            injuryName: null,
            cues: [Cue(title: 'Stand tall.')],
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ExerciseDemoStage(
            exercise: PlanExercise(
              planExerciseId: 1,
              exerciseId: 1,
              name: 'Squat',
              muscleGroup: 'quads',
              orderNo: 1,
              targetSets: 2,
              targetReps: '8-12',
            ),
            positionLabel: _label,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Laid out at its full one-line width: not clipped to "…", not broken in two.
void _expectWhole(WidgetTester tester) {
  final target = tester.renderObject<RenderParagraph>(find.text(_target));
  expect(target.didExceedMaxLines, isFalse);
  expect(
    target.size.width,
    moreOrLessEquals(target.getMaxIntrinsicWidth(double.infinity)),
  );
}

void main() {
  // The test font draws every glyph a full em wide, wider than the app's mono
  // face, so the widths here run large: at 480 the counter (168), a gap and
  // the target (239) fit with about 30 to spare -- unless the target is held
  // to half the free width (140), which is what cut it off on a phone.
  testWidgets('with room for both, the target shows whole beside the counter', (
    tester,
  ) async {
    await _pumpAtWidth(tester, 480);

    expect(tester.takeException(), isNull);
    _expectWhole(tester);
    expect(
      tester.getCenter(find.text(_target)).dy,
      moreOrLessEquals(tester.getCenter(find.text(_label)).dy),
    );
    // Flush with the right edge of the content, as the name below it is.
    expect(
      tester.getTopRight(find.text(_target)).dx,
      moreOrLessEquals(tester.getTopRight(find.text('Squat')).dx),
    );
  });

  // At 320 the two cannot share a line but the target alone fits: a small
  // phone at large text.
  testWidgets(
    'without room for both, the target drops under the counter, whole',
    (tester) async {
      await _pumpAtWidth(tester, 320);

      expect(tester.takeException(), isNull);
      _expectWhole(tester);
      expect(
        tester.getTopLeft(find.text(_target)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text(_label)).dy),
      );
      expect(
        tester.getTopLeft(find.text(_target)).dx,
        moreOrLessEquals(tester.getTopLeft(find.text(_label)).dx),
      );
    },
  );
}
