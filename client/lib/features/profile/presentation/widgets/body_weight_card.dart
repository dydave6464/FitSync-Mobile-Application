import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_charts.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/body_weight.dart';

/// The Progress tab's body-weight card: a chart when there is data, or a
/// prompt to log a first entry when there is not.
class BodyWeightCard extends StatelessWidget {
  const BodyWeightCard({super.key, required this.series, this.onAdd});

  final BodyWeightSeries series;

  /// `FsChip` takes a NON-nullable `onTap`, so the card supplies a no-op when
  /// no handler is given — which is what the widget tests pump.
  final VoidCallback? onAdd;

  VoidCallback get _add => onAdd ?? () {};

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final points = series.points;

    if (points.isEmpty) {
      return FsCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FsEyebrow('Body weight'),
          const SizedBox(height: 6),
          Text('Log your weight to start the chart.',
              style: TextStyle(fontSize: 12, color: t.text3)),
          const SizedBox(height: 10),
          FsChip(label: 'Add entry', selected: false, onTap: _add),
        ],
      ));
    }

    // Everything on `series` is kilograms -- `unit` is display metadata only
    // (see body_weight.dart). Converting once here, rather than per-field,
    // is what keeps the headline, the chart, the reference line and the
    // noise band all reading as the same unit instead of a half-converted
    // card.
    final unit = WeightUnit.fromApi(series.unit);
    final latest = points.last.weightKg;
    final reference = series.reference;

    return FsCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Headline and goal on one line, as the prototype lays them out: the
        // goal is what the headline is measured against, so it is read beside
        // it rather than hunted for on the chart. The chart draws no y-axis,
        // so a label on the dashed line was the only other place it could
        // live -- floating over data it is not part of.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FsEyebrow('Body weight'),
                  const SizedBox(height: 6),
                  Text(formatWeightWithUnit(latest, unit),
                      style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
            ),
            if (reference != null)
              Text(
                '${reference.label} '
                '${formatWeightWithUnit(reference.weightKg, unit)}',
                style: TextStyle(
                  fontFamily: fsMonoFamily,
                  fontSize: 11,
                  color: t.text3,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FsLineChart(
          // `FsPoint.x` must be a sequential index — the chart's axis-label
          // interval and label lookup both index this list by `x.round()`,
          // so anything else (a date, a day offset) silently mislabels.
          points: [
            for (var i = 0; i < points.length; i++)
              FsPoint(
                x: i.toDouble(),
                y: convertFromKg(points[i].weightKg, unit),
                label: points[i].loggedOn.substring(5),
              ),
          ],
          referenceY: reference == null ? null : convertFromKg(reference.weightKg, unit),
          // Unlabelled: the header above says which line this is and what it
          // sits at. The line itself stays because it is what makes a
          // one-entry card read as a chart rather than a lone dot.
          color: t.blue,
          // The band is meant as "a few hundred grams of daily noise" --
          // converting it alongside the data keeps it that same width in
          // whichever unit is on screen, rather than staying a literal 4,
          // which would mean something far narrower in pounds.
          minYBand: convertFromKg(kBodyWeightBandKg, unit),
          height: 70,
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            series.widened
                ? 'all entries — fewer than two in this period'
                : 'Logged weekly',
            style: TextStyle(fontSize: 11, color: t.text3),
          ),
          FsChip(label: 'Add entry', selected: false, onTap: _add),
        ]),
      ],
    ));
  }
}
