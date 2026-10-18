// The demo stage's "Not for you? Switch exercise" link. The logger hands the
// stage a callback only when a switch is allowed; every other place the stage
// appears -- the pushed route behind the set table's tile -- passes none, and
// must look exactly as it did before the link existed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_cues.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_demo_stage.dart';

Future<void> _pump(WidgetTester tester, {VoidCallback? onSwitch}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        exerciseDetailProvider.overrideWith(
          (ref, id) async => const ExerciseDetail(
            exerciseId: 1,
            name: 'Barbell back squat',
            muscleGroup: 'quadriceps',
            equipment: 'barbell',
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
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: ExerciseDemoStage(
            exercise: const PlanExercise(
              planExerciseId: 1,
              exerciseId: 1,
              name: 'Barbell back squat',
              muscleGroup: 'quadriceps',
              orderNo: 1,
              targetSets: 3,
              targetReps: '8-12',
            ),
            positionLabel: 'Exercise 1 / 6',
            onSwitch: onSwitch,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without a callback there is no link', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('logger.switch')), findsNothing);
    expect(find.textContaining('Switch exercise'), findsNothing);
  });

  testWidgets('with one, the link sits under the chips and calls it', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, onSwitch: () => taps++);

    final link = find.byKey(const Key('logger.switch'));
    expect(link, findsOneWidget);
    expect(
      tester.getTopLeft(link).dy,
      greaterThan(tester.getBottomLeft(find.byType(Chip).first).dy - 1),
    );
    expect(
      tester.getTopLeft(link).dy,
      lessThan(tester.getTopLeft(find.textContaining('Stand tall.')).dy),
    );

    await tester.tap(link);
    expect(taps, 1);
  });

  testWidgets('is a button named "Switch exercise", a full finger tall', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, onSwitch: () {});

    expect(
      tester.getSemantics(find.byKey(const Key('logger.switch'))),
      matchesSemantics(
        label: 'Switch exercise',
        isButton: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('logger.switch'))).height,
      greaterThanOrEqualTo(48),
    );
    handle.dispose();
  });

  // Its own foreground colour overrides the theme's text green for text
  // buttons, so it has to name the text green itself.
  testWidgets('reads in the text green', (tester) async {
    await _pump(tester, onSwitch: () {});

    final label = find.descendant(
      of: find.byKey(const Key('logger.switch')),
      matching: find.byType(RichText),
    );
    expect(
      tester.widget<RichText>(label.first).text.style?.color,
      tester.element(label.first).fs.accentText,
    );
  });

  testWidgets('fits a 320 dp phone at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, onSwitch: () {});

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('logger.switch')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('logger.switch')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Not for you? Switch exercise'), findsOneWidget);
  });
}
