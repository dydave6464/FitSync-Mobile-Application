import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/presentation/equipment_icon.dart';

void main() {
  group('reads both equipment vocabularies', () {
    // The plan and swap paths send curated display names ('Bodyweight');
    // GET /exercises sends the raw catalogue tag ('body weight'). Same
    // exercise, same icon — see the comment in src/db/plans.js about the two
    // vocabularies never being joined.
    test('the curated name and the raw tag agree', () {
      expect(equipmentIcon('Bodyweight'), equipmentIcon('body weight'));
      expect(equipmentIcon('Dumbbells'), equipmentIcon('dumbbell'));
      expect(equipmentIcon('Bands'), equipmentIcon('resistance band'));
      expect(equipmentIcon('Barbell'), equipmentIcon('ez barbell'));
    });

    test('a curated parent covers the children folded under it', () {
      // seed-equipment.js folds cable, smith machine and leverage machine
      // under 'Machines'; the catalogue still names them individually.
      final machines = equipmentIcon('Machines');
      expect(equipmentIcon('cable'), machines);
      expect(equipmentIcon('smith machine'), machines);
      expect(equipmentIcon('leverage machine'), machines);
      expect(equipmentIcon('sled machine'), machines);
    });
  });

  test('body weight gets a body, which a dumbbell never should', () {
    expect(equipmentIcon('body weight'), Icons.accessibility_new);
    expect(equipmentIcon('dumbbell'), isNot(Icons.accessibility_new));
  });

  test('a pull-up bar is not read as a barbell', () {
    // 'barbell' contains 'bar', so naive substring matching collapses the two.
    expect(equipmentIcon('Pull-up bar'), isNot(equipmentIcon('Barbell')));
  });

  test('anything unrecognised still gets an icon, never a blank', () {
    for (final unknown in [null, '', 'jet engine', 'tire']) {
      expect(equipmentIcon(unknown), isA<IconData>());
    }
  });
}
