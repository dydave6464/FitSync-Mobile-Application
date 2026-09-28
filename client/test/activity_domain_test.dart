import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/activity/domain/activity.dart';

Map<String, dynamic> _day(String date, int? steps) => {
  'date': date,
  'steps': steps,
  'caloriesBurned': steps == null ? null : 158,
  'distanceKm': steps == null ? null : 4.52,
  'activeMinutes': steps == null ? null : 64,
};

void main() {
  test('formatSteps groups thousands', () {
    expect(formatSteps(0), '0');
    expect(formatSteps(999), '999');
    expect(formatSteps(6420), '6,420');
    expect(formatSteps(100000), '100,000');
  });

  test('usualLine at each boundary', () {
    expect(usualLine(today: 6420, usual: null), 'Your usual appears after 3 days of walking');
    expect(usualLine(today: 6420, usual: 5180), '1,240 above your usual');
    expect(usualLine(today: 4350, usual: 5180), '830 to reach your usual');
    // within 1% of 5000 is 50 steps either way
    expect(usualLine(today: 5040, usual: 5000), 'Matched your usual');
    expect(usualLine(today: 4950, usual: 5000), 'Matched your usual');
    expect(usualLine(today: 5051, usual: 5000), '51 above your usual');
    expect(usualLine(today: 0, usual: 0), 'Matched your usual');
  });

  test('a week parses, with today last and empty days null', () {
    final week = ActivityWeek.fromJson({
      'days': [
        _day('2026-09-22', 3000),
        _day('2026-09-23', null),
        _day('2026-09-24', 5000),
        _day('2026-09-25', null),
        _day('2026-09-26', null),
        _day('2026-09-27', 4000),
        _day('2026-09-28', 6420),
      ],
      'usual': 4000,
      'usualDays': 3,
      'missing': ['weight'],
    });
    expect(week.today.date, '2026-09-28');
    expect(week.today.distanceKm, 4.52);
    expect(week.days[1].steps, isNull);
    expect(week.usual, 4000);
    expect(week.missingWeight, isTrue);
    expect(week.missingHeight, isFalse);
    // (3000 + 5000 + 4000 + 6420) / 4 = 4605
    expect(week.average, 4605);
  });

  test('a week with no data has no average', () {
    final week = ActivityWeek.fromJson({
      'days': [for (var d = 22; d <= 28; d++) _day('2026-09-$d', null)],
      'usual': null,
      'usualDays': 0,
      'missing': <String>[],
    });
    expect(week.average, isNull);
  });

  test('manilaMidnight is 16:00 UTC the day before', () {
    // 2026-09-28 05:00 Manila == 2026-09-27 21:00 UTC
    expect(
      manilaMidnight(DateTime.utc(2026, 9, 27, 21)),
      DateTime.utc(2026, 9, 27, 16),
    );
    // 2026-09-28 23:59 Manila == 2026-09-28 15:59 UTC
    expect(
      manilaMidnight(DateTime.utc(2026, 9, 28, 15, 59)),
      DateTime.utc(2026, 9, 27, 16),
    );
  });
}
