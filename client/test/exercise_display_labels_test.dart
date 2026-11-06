// The catalogue stores its names, muscles and equipment in lowercase
// ('barbell bench press', 'pectorals', 'body weight'), and every screen used
// to show them that way -- while the library's filter says 'Bodyweight' and
// the muscle buttons 'Chest' (SE-10). One display layer, used everywhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_labels.dart';
import 'package:fitsync/features/exercises/presentation/widgets/exercise_demo_body.dart';
import 'package:fitsync/features/exercises/presentation/widgets/exercise_tile.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/domain/encouragement.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_jump_sheet.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_log_panel.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';

const _press = PlanExercise(
  planExerciseId: 1,
  exerciseId: 11,
  name: 'barbell bench press',
  muscleGroup: 'pectorals',
  orderNo: 1,
  targetSets: 1,
  targetReps: '8-12',
);

const _row = PlanExercise(
  planExerciseId: 2,
  exerciseId: 12,
  name: 'cable seated row',
  muscleGroup: 'upper back',
  orderNo: 2,
  targetSets: 1,
  targetReps: '8-12',
);

const _squat = PlanExercise(
  planExerciseId: 3,
  exerciseId: 13,
  name: 'goblet squat',
  muscleGroup: 'quads',
  orderNo: 3,
  targetSets: 1,
  targetReps: '8-12',
);

Widget _host(Widget child) => MaterialApp(
  theme: fsLightTheme(),
  home: Scaffold(body: child),
);

void main() {
  group('the labels', () {
    test('a name starts with a capital, the rest as the catalogue has it', () {
      expect(exerciseDisplayName('barbell bench press'), 'Barbell bench press');
      expect(exerciseDisplayName('3/4 sit-up'), '3/4 sit-up');
      expect(exerciseDisplayName('Incline DB Press'), 'Incline DB Press');
      expect(exerciseDisplayName(''), '');
    });

    test('muscles read as the muscle buttons and plain words do', () {
      expect(muscleLabel('pectorals'), 'Chest');
      expect(muscleLabel('delts'), 'Shoulders');
      expect(muscleLabel('cardiovascular system'), 'Cardio');
      expect(muscleLabel('levator scapulae'), 'Neck');
      expect(muscleLabel('spine'), 'Lower back');
      expect(muscleLabel('upper back'), 'Upper back');
      expect(muscleLabel('glutes'), 'Glutes');
      // A value this does not know is still capitalised, never dropped.
      expect(muscleLabel('quadriceps'), 'Quadriceps');
    });

    test('equipment reads as the filter says it', () {
      expect(equipmentLabel('body weight'), 'Bodyweight');
      expect(equipmentLabel('dumbbell'), 'Dumbbells');
      expect(equipmentLabel('band'), 'Bands');
      expect(equipmentLabel('barbell'), 'Barbell');
      expect(equipmentLabel('ez barbell'), 'EZ barbell');
      expect(equipmentLabel('smith machine'), 'Smith machine');
      // The plan path sends the curated name already; it stays as it is.
      expect(equipmentLabel('Bodyweight'), 'Bodyweight');
    });
  });

  testWidgets('a library row', (tester) async {
    await tester.pumpWidget(
      _host(
        ExerciseTile(
          exercise: const ExerciseSummary(
            exerciseId: 11,
            name: 'barbell bench press',
            muscleGroup: 'pectorals',
            equipment: 'body weight',
            thumbnailUrl: null,
          ),
          baseUrl: 'http://test.local',
          onTap: () {},
          selected: false,
          onInfo: () {},
        ),
      ),
    );

    expect(find.text('Barbell bench press'), findsOneWidget);
    expect(find.text('Chest · Bodyweight'), findsOneWidget);
  });

  testWidgets('the demo: headline and tags', (tester) async {
    await tester.pumpWidget(
      _host(
        const ExerciseDemoBody(
          exercise: ExerciseDetail(
            exerciseId: 11,
            name: 'barbell bench press',
            muscleGroup: 'pectorals',
            equipment: 'body weight',
            thumbnailUrl: null,
            animationUrl: null,
            cues: [],
          ),
          baseUrl: 'http://test.local',
        ),
      ),
    );

    expect(find.text('Barbell bench press'), findsOneWidget);
    expect(find.widgetWithText(FsTag, 'Chest'), findsOneWidget);
    expect(find.widgetWithText(FsTag, 'Bodyweight'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('the set table header', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: ExerciseLogPanel(
            exercise: _press,
            session: const ActiveSession(
              sessionId: 1,
              status: 'in_progress',
              sessionDate: '2026-09-08',
            ),
            drafts: drafts,
            onUndoSet: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Barbell bench press'), findsOneWidget);
  });

  testWidgets('the jump sheet', (tester) async {
    await tester.pumpWidget(
      _host(
        ExerciseJumpSheet(
          exercises: const [_press, _row],
          session: null,
          currentIndex: 0,
        ),
      ),
    );

    expect(find.text('Barbell bench press'), findsOneWidget);
    expect(find.text('Cable seated row'), findsOneWidget);
  });

  test('the encouragement lines', () {
    // Three, so one done is not yet halfway: the line names the exercise.
    final message = encouragementFor(
      exercises: const [_press, _row, _squat],
      index: 0,
      session: const ActiveSession(
        sessionId: 0,
        status: 'in_progress',
        sessionDate: '2026-09-08',
        sets: [LoggedSet(exerciseId: 11, setNumber: 1, reps: 10)],
      ),
    )!;

    expect(message.headline, isNot(contains('barbell bench press')));
    expect(message.headline, contains('Barbell bench press'));
    expect(message.detail, 'Up next: Cable seated row');
  });
}
