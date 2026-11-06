import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/plans/domain/split_style.dart';
import 'package:fitsync/features/plans/domain/week_description.dart';

void main() {
  group('splitLabel', () {
    test('spells a known split as the choosers do', () {
      expect(splitLabel('push_pull_legs'), 'Push / Pull / Legs');
      expect(splitLabel('upper_lower'), 'Upper / Lower');
      expect(splitLabel('full_body'), 'Full body');
      expect(splitLabel('cardio_core'), 'Cardio + core');
    });

    test('falls back to a readable slug for one it does not know', () {
      expect(splitLabel('bro_split'), 'Bro Split');
      expect(splitLabel(''), '');
    });
  });

  group('daysAWeek', () {
    test('says "day" for one and "days" otherwise', () {
      expect(daysAWeek(1), '1 day a week');
      expect(daysAWeek(3), '3 days a week');
      expect(daysAWeek(0), '0 days a week');
    });
  });
}
