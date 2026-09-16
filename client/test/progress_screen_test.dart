import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';

void main() {
  test('muscle bars scale against the largest group', () {
    const a = TrainingAnalytics(
      period: 'week',
      volume: [VolumeBucket(label: '-1d', volumeKg: 0)],
      change: VolumeChange(totalKg: 0, previousKg: 0, changePct: null),
      adherence: Adherence(done: 2, target: 4, weeks: 1),
      muscles: [MuscleSets(muscle: 'chest', sets: 10), MuscleSets(muscle: 'back', sets: 5)],
    );
    expect(a.muscleFraction(a.muscles[0]), 1.0);
    expect(a.muscleFraction(a.muscles[1]), 0.5);
  });

  test('a first week has no percentage to show', () {
    const c = VolumeChange(totalKg: 1100, previousKg: 0, changePct: null);
    expect(c.hasChange, isFalse);
    expect(c.label, '');
  });

  test('a rise reads with its sign', () {
    const c = VolumeChange(totalKg: 1100, previousKg: 1000, changePct: 10);
    expect(c.label, '+10%');
  });

  test('adherence without a target has no ratio to show', () {
    const a = Adherence(done: 3, target: null, weeks: 1);
    expect(a.hasTarget, isFalse);
    expect(a.label, '3');
  });

  test('adherence with a target reads as done over target', () {
    const a = Adherence(done: 14, target: 16, weeks: 4);
    expect(a.hasTarget, isTrue);
    expect(a.label, '14 / 16');
    expect(a.fraction, closeTo(0.875, 0.001));
  });
}
