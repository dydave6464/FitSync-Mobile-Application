import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/plans/domain/training_day.dart';

void main() {
  test('offers a day for every way the splits divide a week', () {
    expect(
      trainingDays.map((d) => d.label),
      ['Full body', 'Upper body', 'Push', 'Pull', 'Legs', 'Cardio & core'],
    );
  });

  test('full body filters nothing', () {
    // splits.py says so in as many words: "Empty means no filter at all:
    // every group is eligible. That is full body."
    expect(trainingDays.first.muscleGroups, isEmpty);
  });

  test('a push day is the groups splits.py gives it', () {
    final push = trainingDays.firstWhere((d) => d.label == 'Push');
    expect(push.muscleGroups, ['pectorals', 'delts', 'triceps']);
  });

  test('a pull day is the groups splits.py gives it', () {
    final pull = trainingDays.firstWhere((d) => d.label == 'Pull');
    expect(pull.muscleGroups, ['lats', 'upper back', 'biceps', 'traps']);
  });

  test('a legs day is the groups splits.py gives it', () {
    final legs = trainingDays.firstWhere((d) => d.label == 'Legs');
    expect(legs.muscleGroups,
        ['quads', 'glutes', 'hamstrings', 'calves', 'adductors', 'abductors']);
  });

  test('upper body is push and pull together, as upper_lower defines it', () {
    final upper = trainingDays.firstWhere((d) => d.label == 'Upper body');
    final push = trainingDays.firstWhere((d) => d.label == 'Push');
    final pull = trainingDays.firstWhere((d) => d.label == 'Pull');
    expect(upper.muscleGroups, [...push.muscleGroups, ...pull.muscleGroups]);
  });

  test('cardio and core is its own pair', () {
    final cardio = trainingDays.firstWhere((d) => d.label == 'Cardio & core');
    expect(cardio.muscleGroups, ['cardiovascular system', 'abs']);
  });

  test('every day but full body actually narrows the catalogue', () {
    // The reason this file exists. Filtering by a whole SPLIT was the first
    // design, and push_pull_legs covered 997 of 1,203 live exercises while
    // upper_lower covered the identical set -- two controls that looked
    // different and were not. A day is the unit that filters.
    for (final day in trainingDays.skip(1)) {
      expect(day.muscleGroups, isNotEmpty, reason: '${day.label} filters nothing');
    }
  });
}
