import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/recovery/domain/recovery.dart';

InjuryRiskEstimate _estimate({
  String level = 'moderate',
  double? score = 50,
  String? source = 'model',
  List<RiskDriver>? drivers,
}) => InjuryRiskEstimate(
  riskLevel: level,
  trainingLoadScore: score,
  checkinDate: '2026-10-18',
  source: source,
  drivers: drivers,
);

/// The reasons' words, in order, or null when there is no list.
List<String>? _why(
  List<RiskDriver>? drivers, {
  String? source = 'model',
  MorningCheckin? today,
}) => _estimate(
  source: source,
  drivers: drivers,
).whyReasons(today: today)?.map((r) => r.text).toList();

/// This morning's check-in, everyday answers unless told otherwise.
MorningCheckin _checkin({
  String sleepQuality = 'good',
  String muscleSoreness = 'mild',
  String energy = 'moderate',
  String stress = 'low',
}) => MorningCheckin(
  checkinId: 1,
  checkinDate: '2026-10-18',
  sleepQuality: sleepQuality,
  muscleSoreness: muscleSoreness,
  energy: energy,
  stress: stress,
);

/// A check-in whose answer to [key] is [value], everyday elsewhere.
MorningCheckin _answering(String key, String value) => switch (key) {
  'sleep' => _checkin(sleepQuality: value),
  'soreness' => _checkin(muscleSoreness: value),
  'energy' => _checkin(energy: value),
  _ => _checkin(stress: value),
};

void main() {
  group('the line under the ring', () {
    test('says what each level means and what to do', () {
      expect(_estimate(level: 'low').levelAdvice, 'Train as planned.');
      expect(
        _estimate(level: 'moderate').levelAdvice,
        'Train, but go a little easier.',
      );
      expect(
        _estimate(level: 'high').levelAdvice,
        'Consider a lighter day: mobility or rest.',
      );
    });
  });

  group('the ring fill', () {
    test('follows the score, not a fixed amount per level', () {
      expect(_estimate(level: 'low', score: 12).ringValue, closeTo(0.12, 1e-9));
      expect(_estimate(level: 'low', score: 35).ringValue, closeTo(0.35, 1e-9));
      expect(
        _estimate(level: 'moderate', score: 47.25).ringValue,
        closeTo(0.4725, 1e-9),
      );
      expect(_estimate(level: 'high', score: 100).ringValue, 1.0);
    });

    test('an estimate saved without a score falls back to its level', () {
      final low = _estimate(level: 'low', score: null).ringValue;
      final high = _estimate(level: 'high', score: null).ringValue;
      expect(low, greaterThan(0));
      expect(high, greaterThan(low));
      expect(high, lessThanOrEqualTo(1));
    });
  });

  group('the "Why" reasons', () {
    test('a load under 1% still reads as above the usual week', () {
      expect(_why([const RiskDriver(key: 'load', value: 0.3)]), [
        'Training a little above your usual week',
      ]);
      expect(_why([const RiskDriver(key: 'load', value: 0.7)]), [
        'Training 1% above your usual week',
      ]);
    });

    test('only a load at the server cap reads as a floor', () {
      expect(_why([const RiskDriver(key: 'load', value: 130)]), [
        'Training at least 130% above your usual week',
      ]);
      expect(_why([const RiskDriver(key: 'load', value: 131)]), [
        'Training at least 130% above your usual week',
      ]);
      // Under the cap is an exact reading, so it is never "at least 130%",
      // and never rounded up onto the cap's own figure either.
      for (final under in [129.4, 129.5, 129.6, 129.99]) {
        expect(_why([RiskDriver(key: 'load', value: under)]), [
          'Training 129% above your usual week',
        ], reason: '$under');
      }
    });

    test('the reasons outside the check-ins read as plain English', () {
      for (final (driver, words) in [
        (
          const RiskDriver(key: 'load', value: 35.0),
          'Training 35% above your usual week',
        ),
        // A fractional load is rounded, never shown as "34.6%".
        (
          const RiskDriver(key: 'load', value: 34.6),
          'Training 35% above your usual week',
        ),
        (const RiskDriver(key: 'injury_history', value: 1), 'A past injury'),
        (const RiskDriver(key: 'injury_history', value: 2), '2 past injuries'),
        (
          const RiskDriver(key: 'recent_pain', value: 'mild'),
          'Mild pain after a recent workout',
        ),
        (
          const RiskDriver(key: 'recent_pain', value: 'moderate'),
          'Pain after a recent workout',
        ),
        (
          const RiskDriver(key: 'recent_pain', value: 'severe'),
          'Severe pain after a recent workout',
        ),
      ]) {
        expect(_why([driver]), [
          words,
        ], reason: '${driver.key} ${driver.value}');
      }
    });

    // A driver is the worst answer over the estimate's last 3 days. On a
    // first morning that is just this morning's, and "lately" claimed a
    // pattern one check-in cannot show.
    test("a check-in driver that is this morning's answer says today", () {
      for (final (key, value, words) in [
        ('sleep', 'poor', 'Poor sleep today'),
        ('sleep', 'fair', 'Only fair sleep today'),
        ('soreness', 'moderate', 'Sore muscles today'),
        ('soreness', 'severe', 'Very sore muscles today'),
        ('energy', 'low', 'Low energy today'),
        ('energy', 'very_low', 'Very low energy today'),
        ('stress', 'moderate', 'Moderate stress today'),
        ('stress', 'high', 'High stress today'),
      ]) {
        expect(
          _why([
            RiskDriver(key: key, value: value),
          ], today: _answering(key, value)),
          [words],
          reason: '$key $value',
        );
      }
    });

    test('one only an earlier morning gave says the last few days', () {
      // This morning was better, so the worst answer was an earlier day's.
      for (final (key, value, words) in [
        ('sleep', 'poor', 'Poor sleep in the last few days'),
        ('soreness', 'severe', 'Very sore muscles in the last few days'),
        ('energy', 'very_low', 'Very low energy in the last few days'),
        ('stress', 'high', 'High stress in the last few days'),
      ]) {
        expect(_why([RiskDriver(key: key, value: value)], today: _checkin()), [
          words,
        ], reason: '$key $value');
      }
    });

    test('without this morning to compare, it never claims today', () {
      expect(_why([const RiskDriver(key: 'sleep', value: 'fair')]), [
        'Only fair sleep in the last few days',
      ]);
    });

    test('everyday answers have no words, since they are never drivers', () {
      for (final (key, value) in [
        ('sleep', 'good'),
        ('sleep', 'excellent'),
        ('soreness', 'mild'),
        ('soreness', 'none'),
        ('energy', 'moderate'),
        ('stress', 'low'),
      ]) {
        expect(
          _why([RiskDriver(key: key, value: value)]),
          isNull,
          reason: '$key $value',
        );
      }
    });

    test(
      'each driver is its own reason, in the order the server ranked them',
      () {
        final reasons = _estimate(
          drivers: const [
            RiskDriver(key: 'load', value: 60),
            RiskDriver(key: 'soreness', value: 'moderate'),
            RiskDriver(key: 'injury_history', value: 3),
          ],
        ).whyReasons()!;
        expect(reasons.map((r) => r.text), [
          'Training 60% above your usual week',
          'Sore muscles in the last few days',
          '3 past injuries',
        ]);
        // The key goes with the words, so the screen can give each its icon.
        expect(reasons.map((r) => r.key), [
          'load',
          'soreness',
          'injury_history',
        ]);
      },
    );

    test('an empty list with a source means nothing stands out', () {
      expect(_why(const []), isEmpty);
      expect(_why(const [], source: 'rules'), isEmpty);
    });

    test('an estimate from before drivers existed has no reasons', () {
      expect(_why(null), isNull);
      // Older rows can come back with an empty list but no source: the
      // server fills [] for them, and "nothing stands out" would be a claim
      // that estimate never made.
      expect(_why(const [], source: null), isNull);
    });

    test('an unknown driver is skipped rather than shown raw', () {
      expect(
        _why([
          const RiskDriver(key: 'moon_phase', value: 'full'),
          const RiskDriver(key: 'sleep', value: 'poor'),
        ]),
        ['Poor sleep in the last few days'],
      );
      expect(
        _why([const RiskDriver(key: 'moon_phase', value: 'full')]),
        isNull,
      );
    });
  });

  group('the heading over the reasons', () {
    // "Why" under "Train as planned" read as if poor sleep were why all was
    // well. The reasons are what pushed the score up, so the heading says
    // so in the verdict's own terms.
    test('a low estimate calls them worth watching', () {
      expect(
        _estimate(level: 'low').whyHeading(const [
          RiskReason(key: 'sleep', text: 'Poor sleep today'),
        ]),
        'Worth watching',
      );
    });

    test('a moderate or high one says they are raising it', () {
      final reasons = [
        const RiskReason(key: 'sleep', text: 'Poor sleep today'),
      ];
      expect(
        _estimate(level: 'moderate').whyHeading(reasons),
        "What's raising it",
      );
      expect(_estimate(level: 'high').whyHeading(reasons), "What's raising it");
    });

    // The model can lift a score with no one answer over the bar; "What's
    // raising it: nothing stands out" would contradict itself.
    test('with nothing standing out it is worth watching at any level', () {
      for (final level in ['low', 'moderate', 'high']) {
        expect(
          _estimate(level: level).whyHeading(const []),
          'Worth watching',
          reason: level,
        );
      }
    });
  });

  group('the few-check-ins note', () {
    test('says how many check-ins there are while under three', () {
      expect(
        fewCheckinsNote(1),
        'Based on 1 check-in. It gets more accurate as you check in each '
        'morning.',
      );
      expect(
        fewCheckinsNote(2),
        'Based on 2 check-ins. It gets more accurate as you check in each '
        'morning.',
      );
    });

    test('is gone from the third, and when the count is unknown', () {
      expect(fewCheckinsNote(3), isNull);
      expect(fewCheckinsNote(7), isNull);
      // An older server sends no count; nothing is guessed.
      expect(fewCheckinsNote(null), isNull);
      // No check-in means no estimate to qualify.
      expect(fewCheckinsNote(0), isNull);
    });
  });

  group('parsing', () {
    test("the overview reads the server's check-in count", () {
      final o = RecoveryOverview.fromJson({
        'todayCheckin': null,
        'latestEstimate': null,
        'checkinCount': 2,
        'load': [],
      });
      expect(o.checkinCount, 2);
      // An older server sends none; nothing is guessed.
      expect(
        RecoveryOverview.fromJson({
          'todayCheckin': null,
          'latestEstimate': null,
          'load': [],
        }).checkinCount,
        isNull,
      );
    });

    test('an old row without the new fields still parses', () {
      final e = InjuryRiskEstimate.fromJson({
        'riskLevel': 'low',
        'trainingLoadScore': 12.0,
        'checkinDate': '2026-10-01',
      });
      expect(e.source, isNull);
      expect(e.loadPct, isNull);
      expect(e.drivers, isNull);
      expect(e.whyReasons(), isNull);
    });

    test('a new row carries its source, load and drivers', () {
      final e = InjuryRiskEstimate.fromJson({
        'riskLevel': 'moderate',
        'trainingLoadScore': 47.25,
        'checkinDate': '2026-10-18',
        'source': 'model',
        'loadPct': 35,
        'drivers': [
          {'key': 'sleep', 'value': 'poor'},
          {'key': 'load', 'value': 35.0},
          {'key': 'injury_history', 'value': 2},
        ],
      });
      expect(e.source, 'model');
      expect(e.loadPct, 35.0);
      expect(e.drivers!.map((d) => d.key), ['sleep', 'load', 'injury_history']);
      expect(e.whyReasons()!.map((r) => r.text), [
        'Poor sleep in the last few days',
        'Training 35% above your usual week',
        '2 past injuries',
      ]);
    });

    test('an old row as GET returns it has no "Why" reasons', () {
      // GET /api/v1/recovery sends the new fields on every row: null source
      // and load, and an empty drivers list, for one saved before them.
      final e = InjuryRiskEstimate.fromJson({
        'riskLevel': 'moderate',
        'trainingLoadScore': 44.0,
        'checkinDate': '2026-10-01',
        'source': null,
        'loadPct': null,
        'drivers': <Object>[],
      });
      expect(e.source, isNull);
      expect(e.drivers, isEmpty);
      expect(e.whyReasons(), isNull);
    });

    test('a new row with nothing standing out says so', () {
      final e = InjuryRiskEstimate.fromJson({
        'riskLevel': 'low',
        'trainingLoadScore': 12.0,
        'checkinDate': '2026-10-18',
        'source': 'rules',
        'loadPct': 0,
        'drivers': <Object>[],
      });
      expect(e.whyReasons(), isEmpty);
    });

    test('malformed drivers are dropped, not thrown on', () {
      final e = InjuryRiskEstimate.fromJson({
        'riskLevel': 'moderate',
        'trainingLoadScore': 47.25,
        'checkinDate': '2026-10-18',
        'source': 'rules',
        'loadPct': null,
        'drivers': [
          'sleep',
          {'key': 7, 'value': 'poor'},
          {'value': 'poor'},
          {'key': 'stress', 'value': 'high'},
        ],
      });
      expect(e.drivers!.map((d) => d.key), ['stress']);
    });

    test('drivers that are not a list read as absent', () {
      final e = InjuryRiskEstimate.fromJson({
        'riskLevel': 'low',
        'trainingLoadScore': 10,
        'checkinDate': '2026-10-18',
        'source': 'rules',
        'drivers': 'oops',
      });
      expect(e.drivers, isNull);
    });
  });
}
