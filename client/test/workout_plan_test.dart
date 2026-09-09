import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/profile/domain/profile.dart';

/// `Profile.fromJson` requires only these three keys; everything else
/// defaults. `extra` overrides and adds.
Map<String, dynamic> _profileJson(Map<String, dynamic> extra) => {
      'userId': 7,
      'email': 'juan@example.com',
      'fullName': 'Juan Dela Cruz',
      ...extra,
    };

void main() {
  test('PlanExercise reads equipment, and tolerates its absence', () {
    final withEquipment = PlanExercise.fromJson(const {
      'planExerciseId': 201,
      'exerciseId': 1, 'name': 'Bench press', 'muscleGroup': 'chest',
      'orderNo': 1, 'targetSets': 3, 'targetReps': '8-12',
      'equipment': 'Barbell',
    });
    expect(withEquipment.equipment, 'Barbell');

    // exercises.equipment_id is nullable server-side, so this is a real state.
    final without = PlanExercise.fromJson(const {
      'planExerciseId': 202,
      'exerciseId': 2, 'name': 'Plank', 'muscleGroup': 'core',
      'orderNo': 2, 'targetSets': 3, 'targetReps': '30s',
    });
    expect(without.equipment, isNull);
  });

  test('a plan exercise keeps the id of its row in the plan', () {
    final ex = PlanExercise.fromJson(const {
      'planExerciseId': 77,
      'exerciseId': 12,
      'name': 'Push-up',
      'muscleGroup': 'pectorals',
      'orderNo': 1,
      'targetSets': 3,
      'targetReps': '8-12',
    });

    expect(ex.planExerciseId, 77);
  });

  test('Profile reads joinedAt, and tolerates its absence', () {
    expect(
      Profile.fromJson(_profileJson({'joinedAt': '2026-04-11T09:30:00.000Z'})).joinedAt,
      DateTime.utc(2026, 4, 11, 9, 30),
    );
    expect(Profile.fromJson(_profileJson({})).joinedAt, isNull);
  });

  test('a plan exposes only one day of exercises at a time', () {
    final plan = WorkoutPlan.fromJson({
      'planId': 1,
      'name': 'PPL',
      'splitStyle': 'push_pull_legs',
      'daysPerWeek': 3,
      'sessionLengthMin': 45,
      'weekNo': 1,
      'days': [
        {'dayNo': 1, 'name': 'Push'},
        {'dayNo': 2, 'name': 'Pull'},
      ],
      'exercises': [
        {'planExerciseId': 1, 'exerciseId': 10, 'name': 'Bench', 'muscleGroup': 'pectorals',
         'dayNo': 1, 'orderNo': 1, 'targetSets': 3, 'targetReps': '8-12'},
        {'planExerciseId': 2, 'exerciseId': 11, 'name': 'Row', 'muscleGroup': 'lats',
         'dayNo': 2, 'orderNo': 1, 'targetSets': 3, 'targetReps': '8-12'},
      ],
    });

    expect(plan.days.map((d) => d.name), ['Push', 'Pull']);
    expect(plan.exercisesForDay(2).map((e) => e.name), ['Row']);
  });

  test('a plan from a server without days reads as one day', () {
    final plan = WorkoutPlan.fromJson({
      'planId': 1, 'name': 'Old', 'splitStyle': 'full_body',
      'daysPerWeek': 3, 'sessionLengthMin': 45, 'weekNo': 1,
      'exercises': [
        // No dayNo -- what an old server sends -- so this one reads as day 1.
        {'planExerciseId': 1, 'exerciseId': 10, 'name': 'Squat', 'muscleGroup': 'quads',
         'orderNo': 1, 'targetSets': 3, 'targetReps': '8-12'},
        // A second, explicit day. Its presence is what makes the assertion
        // below mean something: a filter that ignored dayNo and returned
        // every exercise for a null day would pass a one-exercise fixture
        // just as well as a correct one.
        {'planExerciseId': 2, 'exerciseId': 11, 'name': 'Row', 'muscleGroup': 'lats',
         'dayNo': 2, 'orderNo': 1, 'targetSets': 3, 'targetReps': '8-12'},
      ],
    });

    expect(plan.exercises.first.dayNo, 1);
    // Null day -- a session stamped before migration 013 -- is day 1, not
    // every day: Row must not leak in alongside Squat.
    expect(plan.exercisesForDay(null).map((e) => e.name), ['Squat']);
  });
}
