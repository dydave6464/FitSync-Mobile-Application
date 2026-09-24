import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/streaks/domain/streaks.dart';

LiftGoal _goal({double? best, String? reachedOn}) => LiftGoal(
  goalId: 1,
  exerciseId: 3,
  exerciseName: 'Bench Press',
  targetKg: 60,
  bestKg: best,
  reachedOn: reachedOn,
);

void main() {
  test(
    'progress is best over target, empty when never logged, full once reached',
    () {
      expect(_goal(best: 45).progress, closeTo(0.75, 1e-9));
      expect(_goal().progress, 0);
      expect(_goal(best: 62.5, reachedOn: '2026-09-12').progress, 1);
      expect(_goal(best: 62.5, reachedOn: '2026-09-12').reached, isTrue);
      expect(_goal(best: 45).reached, isFalse);
    },
  );

  test('formatReachedOn names the day and month, and the year only when not this one', () {
    expect(formatReachedOn('2026-09-12', currentYear: 2026), '12 Sep');
    expect(formatReachedOn('2025-12-30', currentYear: 2026), '30 Dec 2025');
    expect(formatReachedOn('2026-01-01', currentYear: 2026), '1 Jan');
  });
}
