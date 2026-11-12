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
  group('grownTo carries the saved estimates along to the live count', () {
    const saved = ActivityDay(
      date: '2026-09-28',
      steps: 6420,
      caloriesBurned: 158,
      distanceKm: 4.52,
      activeMinutes: 64,
    );

    test('by the share the count has grown since the server saved it', () {
      final grown = saved.grownTo(9630);
      expect(grown.steps, 9630);
      expect(grown.caloriesBurned, 237);
      expect(grown.distanceKm, closeTo(6.78, 1e-9));
      expect(grown.activeMinutes, 96);
      expect(grown.date, '2026-09-28');
    });

    test('unchanged when the count has not moved', () {
      final same = saved.grownTo(6420);
      expect(same.caloriesBurned, 158);
      expect(same.distanceKm, 4.52);
      expect(same.activeMinutes, 64);
    });

    test('left as saved when nothing was saved to grow from', () {
      const none = ActivityDay(
        date: '2026-09-28',
        steps: 0,
        caloriesBurned: 0,
        distanceKm: 0,
        activeMinutes: null,
      );
      final grown = none.grownTo(500);
      expect(grown.steps, 500);
      expect(grown.caloriesBurned, 0);
      expect(grown.distanceKm, 0);
      expect(grown.activeMinutes, isNull);
    });
  });

  group('grownTo with the server\'s per-step factors', () {
    // 170 cm, 70 kg, no sex given: what GET /activity sends as perStep.
    const km = 1.70 * 0.414 / 1000;
    const perStep = ActivityPerStep(
      distanceKm: km,
      caloriesBurned: 0.5 * 70 * km,
      activeMinutes: 0.01,
    );
    const saved = ActivityDay(
      date: '2026-09-28',
      steps: 6420,
      caloriesBurned: 158,
      distanceKm: 4.52,
      activeMinutes: 64,
    );

    test('gives the server\'s exact figures for the live count', () {
      final grown = saved.grownTo(9630, perStep: perStep);
      expect(grown.steps, 9630);
      expect(grown.caloriesBurned, 237);
      expect(grown.distanceKm, 6.78);
      expect(grown.activeMinutes, 96);
      expect(grown.date, '2026-09-28');
    });

    test('rounds as the server does, not by the saved share', () {
      // By share: 4.52 x 7000 / 6420 = 4.928...; the server saves 4.93.
      final grown = saved.grownTo(7000, perStep: perStep);
      expect(grown.distanceKm, 4.93);
      expect(grown.caloriesBurned, 172);
      expect(grown.activeMinutes, 70);
    });

    test('grows from a day saved at 0 steps', () {
      const zero = ActivityDay(
        date: '2026-09-28',
        steps: 0,
        caloriesBurned: 0,
        distanceKm: 0,
        activeMinutes: 0,
      );
      final grown = zero.grownTo(6420, perStep: perStep);
      expect(grown.caloriesBurned, 158);
      expect(grown.distanceKm, 4.52);
      expect(grown.activeMinutes, 64);
    });

    test('grows from a day with nothing saved', () {
      const none = ActivityDay(
        date: '2026-09-28',
        steps: null,
        caloriesBurned: null,
        distanceKm: null,
        activeMinutes: null,
      );
      final grown = none.grownTo(6420, perStep: perStep);
      expect(grown.caloriesBurned, 158);
      expect(grown.distanceKm, 4.52);
      expect(grown.activeMinutes, 64);
    });

    test('a missing factor keeps the stored value', () {
      // No height: neither km nor kcal can be worked out.
      const noHeight = ActivityPerStep(
        distanceKm: null,
        caloriesBurned: null,
        activeMinutes: 0.01,
      );
      const stored = ActivityDay(
        date: '2026-09-28',
        steps: 6420,
        caloriesBurned: 0,
        distanceKm: 0,
        activeMinutes: 64,
      );
      final grown = stored.grownTo(9630, perStep: noHeight);
      expect(grown.distanceKm, 0);
      expect(grown.caloriesBurned, 0);
      expect(grown.activeMinutes, 96);

      // No weight: km grows, kcal stays.
      const noWeight = ActivityPerStep(
        distanceKm: 1.70 * 0.414 / 1000,
        caloriesBurned: null,
        activeMinutes: 0.01,
      );
      final partly = stored.grownTo(9630, perStep: noWeight);
      expect(partly.distanceKm, 6.78);
      expect(partly.caloriesBurned, 0);
    });
  });

  group('the week reads perStep', () {
    Map<String, dynamic> week([Map<String, dynamic>? extra]) => {
      'days': [_day('2026-09-28', 6420)],
      'usual': null,
      'usualDays': 0,
      'missing': <String>[],
      ...?extra,
    };

    test('with its factors, as sent', () {
      final w = ActivityWeek.fromJson(
        week({
          'perStep': {
            'distanceKm': 0.0007038,
            'caloriesBurned': 0.024633,
            'activeMinutes': 0.01,
          },
          'skipped': ['2026-09-20'],
        }),
      );
      expect(w.perStep!.distanceKm, 0.0007038);
      expect(w.perStep!.caloriesBurned, 0.024633);
      expect(w.perStep!.activeMinutes, 0.01);
    });

    test('with null factors for a missing height or weight', () {
      final w = ActivityWeek.fromJson(
        week({
          'perStep': {
            'distanceKm': null,
            'caloriesBurned': null,
            'activeMinutes': 0.01,
          },
        }),
      );
      expect(w.perStep!.distanceKm, isNull);
      expect(w.perStep!.caloriesBurned, isNull);
    });

    test('as null from a server that does not send it', () {
      expect(ActivityWeek.fromJson(week()).perStep, isNull);
    });
  });

  test('formatSteps groups thousands', () {
    expect(formatSteps(0), '0');
    expect(formatSteps(999), '999');
    expect(formatSteps(6420), '6,420');
    expect(formatSteps(100000), '100,000');
  });

  test('usualLine at each boundary', () {
    expect(
      usualLine(today: 6420, usual: null),
      'Your usual appears after 3 days of walking',
    );
    expect(usualLine(today: 6420, usual: 5180), '1,240 above your usual');
    expect(usualLine(today: 4350, usual: 5180), '830 to reach your usual');
    // within 1% of 5000 is 50 steps either way
    expect(usualLine(today: 5040, usual: 5000), 'Matched your usual');
    expect(usualLine(today: 4950, usual: 5000), 'Matched your usual');
    expect(usualLine(today: 5051, usual: 5000), '51 above your usual');
    expect(usualLine(today: 0, usual: 0), 'Matched your usual');
  });

  test('before there is a usual, the line counts down the days it needs', () {
    expect(
      usualLine(today: 6420, usual: null, usualDays: 0),
      'Your usual appears after 3 days of walking',
    );
    expect(
      usualLine(today: 6420, usual: null, usualDays: 1),
      'Your usual appears after 2 more days of walking',
    );
    expect(
      usualLine(today: 6420, usual: null, usualDays: 2),
      'Your usual appears after 1 more day of walking',
    );
  });

  test('the per-day average reads in thousands, and below one as steps', () {
    expect(perDayLine(4884), 'avg 4.9k/day');
    expect(perDayLine(1000), 'avg 1.0k/day');
    expect(perDayLine(420), 'avg 420/day');
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
    expect(week.usualDays, 3);
    expect(week.missingWeight, isTrue);
    expect(week.missingHeight, isFalse);
    // The days before today, as the usual is worked out: today's partial
    // count is left out. (3000 + 5000 + 4000) / 3 = 4000.
    expect(week.average, 4000);
  });

  test('a week with only today has no average yet', () {
    final week = ActivityWeek.fromJson({
      'days': [
        for (var d = 22; d <= 27; d++) _day('2026-09-$d', null),
        _day('2026-09-28', 6420),
      ],
      'usual': null,
      'usualDays': 0,
      'missing': <String>[],
    });
    expect(week.average, isNull);
    expect(
      const ActivityWeek(days: [], usual: null, missing: []).average,
      isNull,
    );
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
