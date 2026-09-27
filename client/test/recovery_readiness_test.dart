import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/recovery/domain/recovery.dart';

InjuryRiskEstimate _estimate(String level, double? score) => InjuryRiskEstimate(
  riskLevel: level,
  trainingLoadScore: score,
  checkinDate: '2026-09-24',
);

void main() {
  test('readiness is 100 minus the risk score, on the bands\' side', () {
    expect(_estimate('low', 0).readiness, 100);
    expect(_estimate('low', 4).readiness, 96);
    // Ceiling, not rounding: a low risk never reads as fair's 60, and a
    // moderate one never as good's 61.
    expect(_estimate('low', 39.99).readiness, 61);
    expect(_estimate('moderate', 40).readiness, 60);
    expect(_estimate('moderate', 69.99).readiness, 31);
    expect(_estimate('high', 70).readiness, 30);
    expect(_estimate('high', 100).readiness, 0);
  });

  test('an estimate saved without a score has no readiness number', () {
    expect(_estimate('low', null).readiness, isNull);
  });

  test('the band follows the risk level', () {
    expect(_estimate('low', 10).recoveryLabel, 'Recovery good');
    expect(_estimate('moderate', 50).recoveryLabel, 'Recovery fair');
    expect(_estimate('high', 80).recoveryLabel, 'Recovery low');
    expect(_estimate('low', 10).readinessHeadline, "You're primed to train");
    expect(
      _estimate('moderate', 50).readinessHeadline,
      'Train, but go a little easier',
    );
    expect(_estimate('high', 80).readinessHeadline, 'Consider a lighter day');
  });
}
