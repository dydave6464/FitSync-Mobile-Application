import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/presentation/widgets/coaching_tag.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_jump_sheet.dart';

Map<String, dynamic> _row({Object? coaching}) => {
  'planExerciseId': 7,
  'exerciseId': 41,
  'name': 'glute bridge',
  'muscleGroup': 'glutes',
  'orderNo': 1,
  'targetSets': 2,
  'targetReps': '8-12',
  'dayNo': 3,
  'coaching': coaching,
};

void main() {
  test('a plan row reads its coaching', () {
    final e = PlanExercise.fromJson(
      _row(coaching: {'injuryId': 3, 'injuryName': 'Knee'}),
    );
    expect(e.coaching?.injuryId, 3);
    expect(e.coaching?.injuryName, 'Knee');
  });

  test('a missing or malformed coaching reads as none', () {
    expect(PlanExercise.fromJson(_row()).coaching, isNull);
    expect(PlanExercise.fromJson(_row(coaching: 'Knee')).coaching, isNull);
    expect(
      PlanExercise.fromJson(_row(coaching: {'injuryName': 'Knee'})).coaching,
      isNull,
    );
    final noField = _row()..remove('coaching');
    expect(PlanExercise.fromJson(noField).coaching, isNull);
  });

  testWidgets('the tag names the injury and says AI coached', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CoachingTag(injuryName: 'Knee')),
      ),
    );
    expect(find.text('Knee · AI coached'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('the jump sheet tags only coached exercises', (tester) async {
    final coached = PlanExercise.fromJson(
      _row(coaching: {'injuryId': 3, 'injuryName': 'Knee'}),
    );
    final plain = PlanExercise.fromJson({
      ..._row(),
      'planExerciseId': 8,
      'exerciseId': 42,
      'name': 'push-up',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // session: null reads every exercise as having nothing logged,
          // which is all this test needs.
          body: ExerciseJumpSheet(
            exercises: [coached, plain],
            session: null,
            currentIndex: 0,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('coaching.jump.7')), findsOneWidget);
    expect(find.byKey(const Key('coaching.jump.8')), findsNothing);

    // The tag adds a second line under the name, which must not push the
    // index number down with it -- the number has to stay level with the
    // name's own top, exactly as it is for a row with no tag.
    expect(
      tester.getTopLeft(find.text('1')).dy,
      tester.getTopLeft(find.text('glute bridge')).dy,
    );
  });
}
