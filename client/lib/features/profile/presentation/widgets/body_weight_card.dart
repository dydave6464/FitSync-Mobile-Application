import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
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

    final latest = points.last.weightKg;
    final reference = series.reference;

    return FsCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('Body weight'),
        const SizedBox(height: 6),
        Text('${latest.toStringAsFixed(1)} ${series.unit}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        FsLineChart(
          // `FsPoint.x` must be a sequential index — the chart's axis-label
          // interval and label lookup both index this list by `x.round()`,
          // so anything else (a date, a day offset) silently mislabels.
          points: [
            for (var i = 0; i < points.length; i++)
              FsPoint(
                x: i.toDouble(),
                y: points[i].weightKg,
                label: points[i].loggedOn.substring(5),
              ),
          ],
          referenceY: reference?.weightKg,
          referenceLabel: reference?.label,
          minYBand: kBodyWeightBandKg,
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
