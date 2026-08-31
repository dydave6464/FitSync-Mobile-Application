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
      'exerciseId': 1, 'name': 'Bench press', 'muscleGroup': 'chest',
      'orderNo': 1, 'targetSets': 3, 'targetReps': '8-12',
      'equipment': 'Barbell',
    });
    expect(withEquipment.equipment, 'Barbell');

    // exercises.equipment_id is nullable server-side, so this is a real state.
    final without = PlanExercise.fromJson(const {
      'exerciseId': 2, 'name': 'Plank', 'muscleGroup': 'core',
      'orderNo': 2, 'targetSets': 3, 'targetReps': '30s',
    });
    expect(without.equipment, isNull);
  });

  test('Profile reads joinedAt, and tolerates its absence', () {
    expect(
      Profile.fromJson(_profileJson({'joinedAt': '2026-04-11T09:30:00.000Z'})).joinedAt,
      DateTime.utc(2026, 4, 11, 9, 30),
    );
    expect(Profile.fromJson(_profileJson({})).joinedAt, isNull);
  });
}
