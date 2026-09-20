import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// The ONLY file in the app that imports `fl_chart`.
///
/// Every screen speaks [FsPoint] and these two widgets instead, so swapping or
/// dropping the package later touches one file rather than every card that
/// draws something.

/// How narrow a y-axis window may get before it starts exaggerating noise.
/// Body weight moves by a few hundred grams a day for reasons that have
/// nothing to do with training; 4 kg keeps that looking like the nothing it is.
const kBodyWeightBandKg = 4.0;

/// Wider, because a one-rep max that moved 2 kg genuinely did not move much.
const kStrengthBandKg = 10.0;

class FsPoint {
  const FsPoint({required this.x, required this.y, required this.label});

  final double x;
  final double y;

  /// What the x-axis prints under this point — a date, or a set number.
  final String label;
}

class FsLineChart extends StatelessWidget {
  const FsLineChart({
    super.key,
    required this.points,
    required this.minYBand,
    this.referenceY,
    this.referenceLabel,
    this.color,
    this.height = 84,
  });

  final List<FsPoint> points;

  /// The narrowest y window allowed, in the series' own unit.
  final double minYBand;

  /// A dashed horizontal line behind the series — a goal or starting weight.
  /// It is also what makes a one-point card read as a chart.
  final double? referenceY;
  final String? referenceLabel;

  /// The series' own colour. Null is the accent, which is what a chart of
  /// training output uses. Body weight is not training output -- it is the
  /// body the training acts on -- and reads in blue so the two are not
  /// skimmed as the same measure.
  final Color? color;

  final double height;

  /// The y window actually drawn: the data's range, widened to [minYBand]
  /// around its midpoint when the data is flatter than that, and always
  /// including [referenceY] so the dashed line cannot fall off the card.
  (double, double) get resolvedYRange {
    final values = [
      ...points.map((p) => p.y),
      if (referenceY != null) referenceY!,
    ];
    if (values.isEmpty) return (0, minYBand);

    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);

    final span = hi - lo;
    if (span < minYBand) {
      final mid = (hi + lo) / 2;
      lo = mid - minYBand / 2;
      hi = mid + minYBand / 2;
    } else {
      // Breathing room so the line never touches the card's edge.
      final pad = span * 0.1;
      lo -= pad;
      hi += pad;
    }
    return (lo, hi);
  }

  /// Label every point while there are few, then thin out, so forty dates do
  /// not collide into a grey smear.
  double get _labelInterval => (points.length / 6).ceilToDouble().clamp(1, 60);

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final (minY, maxY) = resolvedYRange;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: points.isEmpty ? 0 : points.first.x,
          maxX: points.isEmpty ? 1 : points.last.x,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: _labelInterval,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Text(
                    points[i].label,
                    style: TextStyle(fontSize: 9, color: t.text3),
                  );
                },
              ),
            ),
          ),
          extraLinesData: referenceY == null
              ? const ExtraLinesData()
              : ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: referenceY!,
                    color: t.text3,
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                    label: HorizontalLineLabel(
                      show: referenceLabel != null,
                      labelResolver: (_) => referenceLabel!,
                      style: TextStyle(fontSize: 9, color: t.text3),
                    ),
                  ),
                ]),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final p in points) FlSpot(p.x, p.y)],
              isCurved: true,
              curveSmoothness: 0.2,
              color: color ?? t.accent,
              barWidth: 2,
              // A single point has no line to draw, so show the dot itself.
              dotData: FlDotData(show: points.length == 1),
              belowBarData: BarAreaData(
                show: true,
                color: (color ?? t.accent).withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled bar, scaled against the largest value in its group rather
/// than a target. A per-muscle weekly target is a claim about training
/// science this app is not in a position to make.
class FsBarRow extends StatelessWidget {
  const FsBarRow({
    super.key,
    required this.label,
    required this.fraction,
    this.color,
  });

  final String label;
  final double fraction;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: TextStyle(fontSize: 11, color: t.text2)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: fraction.clamp(0, 1),
                minHeight: 8,
                backgroundColor: t.surface2,
                color: color ?? t.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
