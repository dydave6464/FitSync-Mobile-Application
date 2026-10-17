import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/domain/muscle_regions.dart';

void main() {
  group('regionOf', () {
    // Every muscle_group value in server/src/db/seeds/exercises.json. One left
    // out would drop its exercises from every region button and from names.
    for (final (muscle, region) in [
      ('pectorals', MuscleRegion.chest),
      ('serratus anterior', MuscleRegion.chest),
      ('upper back', MuscleRegion.back),
      ('lats', MuscleRegion.back),
      ('traps', MuscleRegion.back),
      ('spine', MuscleRegion.back),
      ('levator scapulae', MuscleRegion.back),
      ('glutes', MuscleRegion.legs),
      ('quads', MuscleRegion.legs),
      ('hamstrings', MuscleRegion.legs),
      ('calves', MuscleRegion.legs),
      ('adductors', MuscleRegion.legs),
      ('abductors', MuscleRegion.legs),
      ('delts', MuscleRegion.shoulders),
      ('biceps', MuscleRegion.arms),
      ('triceps', MuscleRegion.arms),
      ('forearms', MuscleRegion.arms),
      ('abs', MuscleRegion.core),
      ('cardiovascular system', MuscleRegion.cardio),
    ]) {
      test('$muscle is $region', () => expect(regionOf(muscle), region));
    }

    test('a muscle group it does not know belongs to no region', () {
      expect(regionOf('neck'), isNull);
    });
  });

  test('each region lists exactly the muscle groups that map to it', () {
    for (final region in MuscleRegion.values) {
      for (final muscle in region.muscleGroups) {
        expect(regionOf(muscle), region, reason: muscle);
      }
    }
  });

  group('manualWorkoutName', () {
    for (final (muscles, want) in [
      (<String>['pectorals'], 'Chest workout'),
      (<String>['cardiovascular system'], 'Cardio workout'),
      // The region with more exercises leads.
      (<String>['triceps', 'pectorals', 'pectorals'], 'Chest & Arms workout'),
      // A tie keeps the regions in their usual order: chest before back.
      (<String>['lats', 'pectorals'], 'Chest & Back workout'),
      // Unknown values are ignored, not named.
      (<String>['quads', 'neck'], 'Legs workout'),
      (<String>['pectorals', 'lats', 'delts'], 'Upper body workout'),
      (<String>['pectorals', 'lats', 'delts', 'biceps'], 'Upper body workout'),
      (<String>['pectorals', 'quads', 'abs'], 'Full body workout'),
    ]) {
      test('$muscles reads "$want"', () {
        expect(manualWorkoutName(muscles), want);
      });
    }

    test('nothing it can name gives null, for the caller to fall back', () {
      expect(manualWorkoutName(const []), isNull);
      expect(manualWorkoutName(const ['neck']), isNull);
    });
  });
}
