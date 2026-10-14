import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/onboarding/domain/daily_targets.dart';

/// The server's food-log target at maintenance must equal this estimate.
/// Both sides read the same fixture; flutter test runs from client/.
void main() {
  final cases = (jsonDecode(
    File('../server/tests/fixtures/daily-targets-parity.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  for (final c in cases) {
    test('maintenance for ${c['sex']} ${c['dateOfBirth']} matches the server', () {
      final t = estimateDailyTargets(
        sex: c['sex'] as String,
        dateOfBirth: c['dateOfBirth'] as String,
        heightCm: (c['heightCm'] as num).toDouble(),
        weightKg: (c['weightKg'] as num).toDouble(),
        activityLevel: c['activityLevel'] as String,
        today: DateTime.parse(c['today'] as String),
      )!;
      expect(t.kcal, c['kcal']);
      expect(t.proteinG, c['proteinG']);
    });
  }
}
