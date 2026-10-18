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

String? _why(List<RiskDriver>? drivers, {String? source = 'model'}) =>
    _estimate(source: source, drivers: drivers).whyLine;

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

  group('the "Why" line', () {
    test('a load under 1% still reads as above the usual week', () {
      expect(
        _why([const RiskDriver(key: 'load', value: 0.3)]),
        'Why: this week is a little above your usual.',
      );
      expect(
        _why([const RiskDriver(key: 'load', value: 0.7)]),
        'Why: this week is 1% above your usual.',
      );
    });

    test('only a load at the server cap reads as a floor', () {
      expect(
        _why([const RiskDriver(key: 'load', value: 130)]),
        'Why: this week is at least 130% above your usual.',
      );
      expect(
        _why([const RiskDriver(key: 'load', value: 131)]),
        'Why: this week is at least 130% above your usual.',
      );
      // Under the cap is an exact reading, so it is never "at least 130%",
      // and never rounded up onto the cap's own figure either.
      for (final under in [129.5, 129.6, 129.99]) {
        expect(
          _why([RiskDriver(key: 'load', value: under)]),
          'Why: this week is 129% above your usual.',
          reason: '$under',
        );
      }
      expect(
        _why([const RiskDriver(key: 'load', value: 129.4)]),
        'Why: this week is 129% above your usual.',
      );
    });

    test('the clauses outside the check-ins read as plain English', () {
      expect(
        _why([const RiskDriver(key: 'load', value: 35.0)]),
        'Why: this week is 35% above your usual.',
      );
      expect(
        _why([const RiskDriver(key: 'injury_history', value: 1)]),
        'Why: you have a past injury.',
      );
      expect(
        _why([const RiskDriver(key: 'injury_history', value: 2)]),
        'Why: you have 2 past injuries.',
      );
      expect(
        _why([const RiskDriver(key: 'recent_pain', value: 'moderate')]),
        'Why: you reported pain after a recent workout.',
      );
      expect(
        _why([const RiskDriver(key: 'recent_pain', value: 'mild')]),
        'Why: you reported mild pain after a recent workout.',
      );
      expect(
        _why([const RiskDriver(key: 'recent_pain', value: 'severe')]),
        'Why: you reported severe pain after a recent workout.',
      );
      // A fractional load is rounded, never shown as "34.6%".
      expect(
        _why([const RiskDriver(key: 'load', value: 34.6)]),
        'Why: this week is 35% above your usual.',
      );
    });

    test('check-in drivers are worded as the recent check-ins, not today', () {
      for (final (key, value, noun) in [
        ('sleep', 'poor', 'poor sleep'),
        ('sleep', 'fair', 'only fair sleep'),
        ('soreness', 'moderate', 'sore muscles'),
        ('soreness', 'severe', 'very sore muscles'),
        ('energy', 'low', 'low energy'),
        ('energy', 'very_low', 'very low energy'),
        ('stress', 'moderate', 'moderate stress'),
        ('stress', 'high', 'high stress'),
      ]) {
        expect(
          _why([RiskDriver(key: key, value: value)]),
          'Why: recent check-ins show $noun.',
          reason: '$key $value',
        );
      }
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

    test('check-in drivers share one "recent check-ins show" list', () {
      expect(
        _why([
          const RiskDriver(key: 'sleep', value: 'poor'),
          const RiskDriver(key: 'stress', value: 'high'),
        ]),
        'Why: recent check-ins show poor sleep and high stress.',
      );
      expect(
        _why([
          const RiskDriver(key: 'soreness', value: 'severe'),
          const RiskDriver(key: 'sleep', value: 'fair'),
          const RiskDriver(key: 'energy', value: 'very_low'),
        ]),
        'Why: recent check-ins show very sore muscles, only fair sleep and '
        'very low energy.',
      );
    });

    test('a comma sets the check-in list apart from the other clauses', () {
      expect(
        _why([
          const RiskDriver(key: 'sleep', value: 'poor'),
          const RiskDriver(key: 'stress', value: 'high'),
          const RiskDriver(key: 'load', value: 35),
        ]),
        'Why: recent check-ins show poor sleep and high stress, and this '
        'week is 35% above your usual.',
      );
      expect(
        _why([
          const RiskDriver(key: 'sleep', value: 'poor'),
          const RiskDriver(key: 'load', value: 35),
        ]),
        'Why: recent check-ins show poor sleep, and this week is 35% above '
        'your usual.',
      );
      // The list keeps the place of its most influential member.
      expect(
        _why([
          const RiskDriver(key: 'load', value: 60),
          const RiskDriver(key: 'soreness', value: 'moderate'),
        ]),
        'Why: this week is 60% above your usual, and recent check-ins show '
        'sore muscles.',
      );
      expect(
        _why([
          const RiskDriver(key: 'recent_pain', value: 'severe'),
          const RiskDriver(key: 'soreness', value: 'moderate'),
          const RiskDriver(key: 'injury_history', value: 3),
        ]),
        'Why: you reported severe pain after a recent workout, recent '
        'check-ins show sore muscles, and you have 3 past injuries.',
      );
    });

    test('without check-in drivers the clauses join with "and"', () {
      expect(
        _why([
          const RiskDriver(key: 'load', value: 35),
          const RiskDriver(key: 'injury_history', value: 1),
        ]),
        'Why: this week is 35% above your usual and you have a past injury.',
      );
      expect(
        _why([
          const RiskDriver(key: 'recent_pain', value: 'moderate'),
          const RiskDriver(key: 'load', value: 35),
          const RiskDriver(key: 'injury_history', value: 2),
        ]),
        'Why: you reported pain after a recent workout, this week is 35% '
        'above your usual and you have 2 past injuries.',
      );
    });

    test('an empty list with a source says nothing stands out', () {
      expect(
        _why(const []),
        'Nothing in your check-ins, training or history stands out.',
      );
      expect(
        _why(const [], source: 'rules'),
        'Nothing in your check-ins, training or history stands out.',
      );
    });

    test('an estimate from before drivers existed has no line', () {
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
        'Why: recent check-ins show poor sleep.',
      );
      expect(
        _why([const RiskDriver(key: 'moon_phase', value: 'full')]),
        isNull,
      );
    });
  });

  group('parsing', () {
    test('an old row without the new fields still parses', () {
      final e = InjuryRiskEstimate.fromJson({
        'riskLevel': 'low',
        'trainingLoadScore': 12.0,
        'checkinDate': '2026-10-01',
      });
      expect(e.source, isNull);
      expect(e.loadPct, isNull);
      expect(e.drivers, isNull);
      expect(e.whyLine, isNull);
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
      expect(
        e.whyLine,
        'Why: recent check-ins show poor sleep, this week is 35% above your '
        'usual, and you have 2 past injuries.',
      );
    });

    test('an old row as GET returns it has no "Why" line', () {
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
      expect(e.whyLine, isNull);
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
      expect(
        e.whyLine,
        'Nothing in your check-ins, training or history stands out.',
      );
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
