import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/plans/domain/plan_energy.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';

WorkoutPlan _plan({
  required int sessionLengthMin,
  required List<String?> equipment,
}) =>
    WorkoutPlan(
      planId: 1,
      name: 'Upper Body · Push',
      splitStyle: 'upper_lower',
      daysPerWeek: 3,
      sessionLengthMin: sessionLengthMin,
      weekNo: 1,
      exercises: [
        for (final (index, item) in equipment.indexed)
          PlanExercise(
            exerciseId: index + 1,
            name: 'Exercise ${index + 1}',
            muscleGroup: 'chest',
            orderNo: index + 1,
            targetSets: 3,
            targetReps: '8-12',
            equipment: item,
          ),
      ],
    );

/// Mirrors `PLAN_ENERGY_EQUIPMENT_NAMES` in
/// `server/tests/equipment-curation.test.js`, which asserts this same list
/// against `OPTIONS[].displayName` — the server's curated equipment chips.
///
/// These two lists are what pin the client's MET table to the server's
/// vocabulary. Nothing else does: the two are otherwise unconnected strings
/// living in different languages, so renaming a chip on the server (a pure
/// presentation change there) would otherwise silently reclassify every
/// exercise using that equipment to the 4.0 fallback MET, with every
/// existing test still green. Keeping both lists in sync is a deliberate,
/// visible edit — either side drifting on its own fails its own test.
const _pinnedEquipmentNames = {
  'Barbell', 'Machines', 'Dumbbells', 'Kettlebell', 'Bodyweight', 'Bands',
};

void main() {
  test('the MET table is keyed on exactly the pinned equipment vocabulary', () {
    expect(metTableEquipmentNames, _pinnedEquipmentNames);
  });

  test('estimates from the plan\'s equipment mix', () {
    // 2 barbell (5.0) + 2 bodyweight (4.0) -> mean MET 4.5
    // 4.5 * 70kg * (60/60) = 315
    final plan = _plan(sessionLengthMin: 60, equipment: const [
      'Barbell', 'Barbell', 'Bodyweight', 'Bodyweight',
    ]);
    expect(estimateSessionKcal(plan: plan, weightKg: 70), 315);
  });

  test('Machines, Dumbbells and Kettlebell each contribute MET 5.0', () {
    // Barbell and Bodyweight already have value assertions above (via the
    // equipment-mix test) and Bands via the relative comparison below, but
    // these three keys had no value assertion anywhere — a typo in any of
    // them would silently fall back to the 4.0 default and go unnoticed.
    // 5.0 * 70kg * (60/60) = 350.
    for (final equipment in ['Machines', 'Dumbbells', 'Kettlebell']) {
      final plan = _plan(sessionLengthMin: 60, equipment: [equipment]);
      expect(estimateSessionKcal(plan: plan, weightKg: 70), 350,
          reason: '$equipment must key to MET 5.0, not the 4.0 fallback');
    }
  });

  test('a band session burns less than a barbell session', () {
    final bands = _plan(sessionLengthMin: 60, equipment: const ['Bands']);
    final barbell = _plan(sessionLengthMin: 60, equipment: const ['Barbell']);
    expect(estimateSessionKcal(plan: bands, weightKg: 70),
        lessThan(estimateSessionKcal(plan: barbell, weightKg: 70)!));
  });

  test('an unmapped or missing equipment name falls back to the mid value', () {
    final unknown = _plan(sessionLengthMin: 60, equipment: const ['Sled machine']);
    final absent = _plan(sessionLengthMin: 60, equipment: const [null]);
    expect(estimateSessionKcal(plan: unknown, weightKg: 70), 280); // 4.0 * 70
    expect(estimateSessionKcal(plan: absent, weightKg: 70), 280);
  });

  test('returns null without a body weight', () {
    final plan = _plan(sessionLengthMin: 60, equipment: const ['Barbell']);
    expect(estimateSessionKcal(plan: plan, weightKg: null), isNull,
        reason: 'an average body weight would be a stranger\'s, not the user\'s');
  });

  test('a plan with no exercises yields null, not a divide by zero', () {
    expect(estimateSessionKcal(plan: _plan(sessionLengthMin: 60, equipment: const []),
        weightKg: 70), isNull);
  });
}
