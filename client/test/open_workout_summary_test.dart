import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/presentation/open_workout_summary.dart';

PlanExercise _picked(int id, String muscle) => PlanExercise(
  planExerciseId: id,
  exerciseId: id,
  name: 'Ex $id',
  muscleGroup: muscle,
  orderNo: id,
  targetSets: 3,
  targetReps: '8-12',
);

ExerciseSummary _summary(int id, String muscle) => ExerciseSummary(
  exerciseId: id,
  name: 'Ex $id',
  muscleGroup: muscle,
  equipment: 'dumbbell',
  thumbnailUrl: null,
);

void main() {
  group('openWorkoutTitle', () {
    test('a hand-picked workout is named by its muscles', () {
      final session = ActiveSession(
        sessionId: 1,
        status: 'in_progress',
        sessionDate: '2026-10-18',
        exercises: [
          _picked(1, 'pectorals'),
          _picked(2, 'triceps'),
          _picked(3, 'pectorals'),
        ],
      );

      expect(openWorkoutTitle(session, null), 'Chest & Arms workout');
    });

    test(
      'a hand-picked workout with nothing to name keeps the plain title',
      () {
        const session = ActiveSession(
          sessionId: 1,
          status: 'in_progress',
          sessionDate: '2026-10-18',
        );

        expect(openWorkoutTitle(session, null), 'Your own workout');
      },
    );
  });

  test('the last workout, when hand-picked, is named by its muscles', () {
    final last = LastWorkout(
      sessionId: 5,
      sessionDate: '2026-10-17',
      exercises: [_summary(1, 'quads'), _summary(2, 'hamstrings')],
    );

    expect(last.title, 'Legs workout');
  });

  test('the last workout from a plan keeps the plan name', () {
    final last = LastWorkout(
      sessionId: 5,
      sessionDate: '2026-10-17',
      planName: 'Push / Pull / Legs',
      exercises: [_summary(1, 'quads')],
    );

    expect(last.title, 'Push / Pull / Legs');
  });
  final now = DateTime(2026, 10, 18, 15, 30);

  group('openedAgo', () {
    for (final (gap, want) in [
      (const Duration(seconds: 20), 'just now'),
      (const Duration(minutes: 1), '1 min ago'),
      (const Duration(minutes: 59, seconds: 59), '59 min ago'),
      (const Duration(hours: 1), '1 h ago'),
      (const Duration(hours: 23, minutes: 59), '23 h ago'),
      (const Duration(hours: 24), 'yesterday'),
      // 16:30 two days back: two calendar days, though under 48 hours.
      (const Duration(hours: 47), '2 days ago'),
      (const Duration(days: 2), '2 days ago'),
      (const Duration(days: 9), '9 days ago'),
    ]) {
      test('$gap before reads "$want"', () {
        expect(openedAgo(now.subtract(gap), now), want);
      });
    }

    test('a day or more counts calendar days, not 24-hour blocks', () {
      // 24 h 40 min, but opened the day before yesterday.
      expect(
        openedAgo(
          DateTime(2026, 10, 16, 23, 30),
          DateTime(2026, 10, 18, 0, 10),
        ),
        '2 days ago',
      );
      // 25 h, and opened the calendar day before.
      expect(
        openedAgo(DateTime(2026, 10, 17, 8), DateTime(2026, 10, 18, 9)),
        'yesterday',
      );
    });

    test('under a day reads in hours even across midnight', () {
      expect(
        openedAgo(DateTime(2026, 10, 17, 23), DateTime(2026, 10, 18, 1)),
        '2 h ago',
      );
    });

    test('a start time ahead of the phone clock reads "just now"', () {
      // The server stamps startedAt; a phone whose clock runs slow sees it a
      // little in the future, which is not "-3 min ago".
      expect(openedAgo(now.add(const Duration(minutes: 3)), now), 'just now');
    });

    test('an unknown start time says nothing', () {
      expect(openedAgo(null, now), isNull);
    });
  });
}
