import 'package:flutter/material.dart';

import '../../../../core/dates.dart';
import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_charts.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/body_weight.dart';

/// The Progress tab's body-weight card: a chart when there is data, or a
/// prompt to log a first entry when there is not.
class BodyWeightCard extends StatelessWidget {
  const BodyWeightCard({
    super.key,
    required this.series,
    this.unit,
    this.onAdd,
  });

  final BodyWeightSeries series;

  /// The unit to show, from `weightUnitProvider`. `series.unit` is the unit
  /// the server saw when the series was fetched, and the series provider is
  /// kept alive and not refetched on a unit switch, so it goes stale the
  /// moment the user flips kg/lb. Null falls back to it, for callers (and
  /// tests) with no live unit to hand.
  final WeightUnit? unit;

  /// `FsChip` takes a NON-nullable `onTap`, so the card supplies a no-op when
  /// no handler is given — which is what the widget tests pump.
  final VoidCallback? onAdd;

  VoidCallback get _add => onAdd ?? () {};

  /// [loggedOn] as a count of days, for spacing weigh-ins by their dates.
  /// Read as UTC midnight: a local one is 23 hours from the next across a
  /// change of clocks, which would count as no day at all.
  static int _dayNumber(String loggedOn) =>
      DateTime.parse('${loggedOn}T00:00:00Z').millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// One weigh-in as the chart draws it: placed by the days since [first],
  /// the first weigh-in's day number, with "Sep 20" under its dot and
  /// "Sep 20 · 72.5 kg" when it is touched.
  static FsPoint _point(BodyWeightPoint point, int first, WeightUnit unit) {
    final day = shortDate(DateTime.parse(point.loggedOn));
    return FsPoint(
      x: (_dayNumber(point.loggedOn) - first).toDouble(),
      y: convertFromKg(point.weightKg, unit),
      label: day,
      tooltip: '$day · ${formatWeightWithUnit(point.weightKg, unit)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final points = series.points;

    if (points.isEmpty) {
      return FsCard(
        // Add entry is the card's last line; the card's padding under it is
        // where the rest of its 48 dp goes.
        child: FsTapRoom(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FsEyebrow('Body weight'),
              const SizedBox(height: 6),
              Text(
                'Log your weight to start the chart.',
                style: TextStyle(fontSize: 12, color: t.text3),
              ),
              const SizedBox(height: 10),
              FsChip(label: 'Add entry', selected: false, onTap: _add),
            ],
          ),
        ),
      );
    }

    // Everything on `series` is kilograms -- `unit` is display metadata only
    // (see body_weight.dart). Converting once here, rather than per-field,
    // is what keeps the headline, the chart, the reference line and the
    // noise band all reading as the same unit instead of a half-converted
    // card.
    final unit = this.unit ?? WeightUnit.fromApi(series.unit);
    final latest = points.last.weightKg;
    final firstDay = _dayNumber(points.first.loggedOn);
    final reference = series.reference;

    return FsCard(
      // As above: the padding under the footer row is Add entry's to use.
      child: FsTapRoom(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The headline alone. The goal used to sit opposite it, the only
            // place the dashed line was named; it is named on the line itself
            // now, where it is drawn.
            const FsEyebrow('Body weight'),
            const SizedBox(height: 6),
            Text(
              formatWeightWithUnit(latest, unit),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            FsLineChart(
              label: 'Body weight',
              // Spaced by date, not by order: a three-week gap between
              // weigh-ins reads as one, rather than as one more week.
              points: [
                for (final point in points) _point(point, firstDay, unit),
              ],
              referenceY: reference == null
                  ? null
                  : convertFromKg(reference.weightKg, unit),
              // Named where it is drawn: "Goal 70 kg". Unlabelled, nothing said
              // what the dashed line was. It stays even for one entry, because
              // it is what makes a lone weigh-in read as a chart.
              referenceLabel: reference == null
                  ? null
                  : '${reference.label} '
                        '${formatWeightWithUnit(reference.weightKg, unit)}',
              color: t.blue,
              // The band is meant as "a few hundred grams of daily noise" --
              // converting it alongside the data keeps it that same width in
              // whichever unit is on screen, rather than staying a literal 4,
              // which would mean something far narrower in pounds.
              minYBand: convertFromKg(kBodyWeightBandKg, unit),
              // Room for a dot on every weigh-in and the dates under them.
              height: 104,
            ),
            const SizedBox(height: 8),
            // The caption takes what the chip leaves and wraps there; as two
            // fixed widths in one row they overflowed it at large text.
            // The row is as tall as the chip, so it needs room of its own
            // for the gap above; the column's carries the padding below.
            FsTapRoom(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      series.widened
                          ? 'all entries — fewer than two in this period'
                          : 'Logged weekly',
                      style: TextStyle(fontSize: 11, color: t.text3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FsChip(label: 'Add entry', selected: false, onTap: _add),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
