import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';

void main() {
  TrainingAnalytics analytics({
    List<MuscleVolume> muscles = const [],
    bool musclesLocked = false,
  }) => TrainingAnalytics(
        period: 'week',
        volume: const [VolumeBucket(label: '-1d', volumeKg: 0)],
        change: const VolumeChange(totalKg: 0, previousKg: 0, changePct: null),
        adherence: const Adherence(done: 2, target: 4, weeks: 1),
        muscles: muscles,
        musclesLocked: musclesLocked,
      );

  test('muscle bars scale against the largest group', () {
    final a = analytics(muscles: const [
      MuscleVolume(muscle: 'chest', volumeKg: 3000),
      MuscleVolume(muscle: 'back', volumeKg: 1500),
    ]);
    expect(a.muscleFraction(a.muscles[0]), 1.0);
    expect(a.muscleFraction(a.muscles[1]), 0.5);
  });

  // Two different empty lists, and the card reads differently for each: one
  // offers an upgrade, the other explains that bodyweight work carries no
  // volume. Without the flag they are indistinguishable.
  test('a locked payload is told apart from an empty one', () {
    expect(analytics(musclesLocked: true).muscles, isEmpty);
    expect(analytics(musclesLocked: true).musclesLocked, isTrue);
    expect(analytics().musclesLocked, isFalse);
  });

  test('muscle volumes are read from the payload', () {
    final a = TrainingAnalytics.fromJson(const {
      'period': 'week',
      'volume': [],
      'change': {'totalKg': 600, 'previousKg': 0, 'changePct': null},
      'adherence': {'done': 1, 'target': 3, 'weeks': 1},
      'muscles': [
        {'muscle': 'chest', 'volumeKg': 600},
        {'muscle': 'lats', 'volumeKg': 450},
      ],
      'musclesLocked': false,
    });

    expect(a.muscles.first.muscle, 'chest');
    expect(a.muscles.first.volumeKg, 600);
    expect(a.musclesLocked, isFalse);
  });

  // A server that predates the flag sends muscles with no lock. Reading the
  // absence as "locked" would hide a card the user is entitled to.
  test('a payload predating the flag is not locked', () {
    final a = TrainingAnalytics.fromJson(const {
      'period': 'week',
      'volume': [],
      'change': {'totalKg': 0, 'previousKg': 0, 'changePct': null},
      'adherence': {'done': 0, 'target': 3, 'weeks': 1},
      'muscles': [],
    });

    expect(a.musclesLocked, isFalse);
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
