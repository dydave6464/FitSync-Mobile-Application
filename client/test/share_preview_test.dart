import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/share_preview.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';

const _summary = TrainingSummary(
  sessionCount: 13,
  setCount: 75,
  totalVolumeKg: 31243.5,
);

TrainingAnalytics _analytics({int? changePct = 21, int? target = 13}) =>
    TrainingAnalytics(
      period: 'month',
      volume: const [],
      change: VolumeChange(
        totalKg: 31243.5,
        previousKg: 25800,
        changePct: changePct,
      ),
      adherence: Adherence(done: 13, target: target, weeks: 4),
      muscles: const [],
    );

BodyWeightSeries _weight({bool widened = false, int points = 2}) =>
    BodyWeightSeries(
      widened: widened,
      points: [
        const BodyWeightPoint(loggedOn: '2026-10-16', weightKg: 76.4),
        const BodyWeightPoint(loggedOn: '2026-11-06', weightKg: 75.2),
      ].take(points).toList(),
      reference: null,
      unit: 'kg',
    );

List<SharePreviewTile> _tiles({
  TrainingSummary? summary = _summary,
  TrainingAnalytics? analytics,
  BodyWeightSeries? bodyWeight,
  bool weightLoading = false,
  bool includeVolume = true,
  bool includeBodyWeight = true,
}) => sharePreviewTiles(
  period: 'month',
  summary: summary,
  analytics: analytics ?? _analytics(),
  bodyWeight: weightLoading ? null : bodyWeight ?? _weight(),
  includeVolume: includeVolume,
  includeBodyWeight: includeBodyWeight,
);

void main() {
  group('shareWindowLabel', () {
    test('a month ends today and starts 29 days back', () {
      expect(
        shareWindowLabel('month', DateTime.utc(2026, 11, 9)),
        'Oct 11 – Nov 9',
      );
    });
    test('a week is seven days, today included', () {
      expect(
        shareWindowLabel('week', DateTime.utc(2026, 11, 9)),
        'Nov 3 – Nov 9',
      );
    });
    test('a window crossing a year names both years', () {
      expect(
        shareWindowLabel('year', DateTime.utc(2026, 11, 9)),
        'Nov 10, 2025 – Nov 9, 2026',
      );
    });
  });

  group('sharePreviewTiles', () {
    test('the four tiles the page opens with', () {
      final tiles = _tiles();
      expect(tiles.map((t) => t.label), [
        'Volume',
        'Sessions',
        'Sets',
        'Body weight',
      ]);
      expect(tiles[0].value, '31.2k kg');
      expect(tiles[0].note, '+21% vs previous month');
      expect(tiles[1].value, '13');
      expect(tiles[1].note, 'of 13 planned');
      expect(tiles[2].value, '75');
      expect(tiles[3].value, '−1.2 kg');
      expect(tiles[3].note, '76.4 → 75.2');
    });

    test('still loading reads as a dash', () {
      final tiles = _tiles(summary: null);
      expect(tiles.take(3).map((t) => t.value), ['–', '–', '–']);
    });

    test('volume rounds to whole kilograms first, as the page does', () {
      TrainingSummary volume(double kg) =>
          TrainingSummary(sessionCount: 1, setCount: 1, totalVolumeKg: kg);
      expect(_tiles(summary: volume(31249.5))[0].value, '31.3k kg');
      expect(_tiles(summary: volume(999.6))[0].value, '1k kg');
      expect(_tiles(summary: volume(1049.6))[0].value, '1.1k kg');
    });

    test('body weight still loading, or failed, reads as a dash', () {
      final tiles = _tiles(weightLoading: true);
      expect(tiles.length, 4);
      expect(tiles[3].label, 'Body weight');
      expect(tiles[3].value, '–');
      expect(tiles[3].note, isNull);
      expect(_tiles(weightLoading: true, includeBodyWeight: false).length, 3);
    });

    test('no target, no "of N planned"', () {
      expect(_tiles(analytics: _analytics(target: null))[1].note, isNull);
    });

    test('no previous window, or volume switched off, no percentage', () {
      expect(_tiles(analytics: _analytics(changePct: null))[0].note, isNull);
      expect(_tiles(includeVolume: false)[0].note, isNull);
    });

    test(
      'the weight tile needs two points in the window, and the section on',
      () {
        expect(_tiles(bodyWeight: _weight(points: 1)).length, 3);
        expect(_tiles(bodyWeight: _weight(widened: true)).length, 3);
        expect(_tiles(includeBodyWeight: false).length, 3);
      },
    );

    test('a gain is signed plus, no change reads 0 kg', () {
      final gain = BodyWeightSeries(
        widened: false,
        points: const [
          BodyWeightPoint(loggedOn: '2026-10-16', weightKg: 75),
          BodyWeightPoint(loggedOn: '2026-11-06', weightKg: 76.5),
        ],
        reference: null,
        unit: 'kg',
      );
      expect(_tiles(bodyWeight: gain)[3].value, '+1.5 kg');
      expect(_tiles(bodyWeight: gain)[3].note, '75 → 76.5');

      final flat = BodyWeightSeries(
        widened: false,
        points: const [
          BodyWeightPoint(loggedOn: '2026-10-16', weightKg: 75),
          BodyWeightPoint(loggedOn: '2026-11-06', weightKg: 75),
        ],
        reference: null,
        unit: 'kg',
      );
      expect(_tiles(bodyWeight: flat)[3].value, '0 kg');
    });
  });
}
