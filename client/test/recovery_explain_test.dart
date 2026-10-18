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

    test('a load at the server cap reads as a floor, not an exact figure', () {
      expect(
        _why([const RiskDriver(key: 'load', value: 130)]),
        'Why: this week is at least 130% above your usual.',
      );
      expect(
        _why([const RiskDriver(key: 'load', value: 129.6)]),
        'Why: this week is at least 130% above your usual.',
      );
      expect(
        _why([const RiskDriver(key: 'load', value: 129.4)]),
        'Why: this week is 129% above your usual.',
      );
    });

    test('each driver reads as plain English', () {
      expect(
        _why([const RiskDriver(key: 'load', value: 35.0)]),
        'Why: this week is 35% above your usual.',
      );
      expect(
        _why([const RiskDriver(key: 'sleep', value: 'poor')]),
        'Why: you slept poorly.',
      );
      expect(
        _why([const RiskDriver(key: 'sleep', value: 'fair')]),
        'Why: you slept fairly.',
      );
      expect(
        _why([const RiskDriver(key: 'soreness', value: 'moderate')]),
        'Why: your muscles are sore.',
      );
      expect(
        _why([const RiskDriver(key: 'energy', value: 'low')]),
        'Why: your energy is low.',
      );
      expect(
        _why([const RiskDriver(key: 'stress', value: 'high')]),
        'Why: your stress is high.',
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
    });

    test('the value changes the wording where it matters', () {
      expect(
        _why([const RiskDriver(key: 'soreness', value: 'mild')]),
        'Why: your muscles are a little sore.',
      );
      expect(
        _why([const RiskDriver(key: 'soreness', value: 'severe')]),
        'Why: your muscles are very sore.',
      );
      expect(
        _why([const RiskDriver(key: 'energy', value: 'very_low')]),
        'Why: your energy is very low.',
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

    test('two drivers are joined by "and", three by commas then "and"', () {
      expect(
        _why([
          const RiskDriver(key: 'sleep', value: 'poor'),
          const RiskDriver(key: 'load', value: 35),
        ]),
        'Why: you slept poorly and this week is 35% above your usual.',
      );
      expect(
        _why([
          const RiskDriver(key: 'recent_pain', value: 'severe'),
          const RiskDriver(key: 'soreness', value: 'moderate'),
          const RiskDriver(key: 'injury_history', value: 3),
        ]),
        'Why: you reported severe pain after a recent workout, your muscles '
        'are sore and you have 3 past injuries.',
      );
    });

    test('an empty list says nothing stands out', () {
      expect(
        _why(const []),
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
        'Why: you slept poorly.',
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
        'Why: you slept poorly, this week is 35% above your usual and you '
        'have 2 past injuries.',
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
