import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// The ONLY file in the app that imports `fl_chart`.
///
/// Every screen speaks [FsPoint], [FsChartBar] and these widgets instead, so
/// swapping or dropping the package later touches one file rather than every
/// card that draws something.

/// How narrow a y-axis window may get before it starts exaggerating noise.
/// Body weight moves by a few hundred grams a day for reasons that have
/// nothing to do with training; 4 kg keeps that looking like the nothing it is.
const kBodyWeightBandKg = 4.0;

/// Wider, because a one-rep max that moved 2 kg genuinely did not move much.
const kStrengthBandKg = 10.0;

/// The axis words under every chart: readable grey at a readable size, not
/// the faint caption colour at 9 px they started as.
TextStyle _axisStyle(FsTokens t) => TextStyle(fontSize: 11, color: t.text2);

/// How tall the strip of axis words is, grown with the user's text size so a
/// larger setting does not crop them.
double _axisSpace(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(11) * 1.4 + 6;

/// The dark chip a touched point or bar reads out in.
TextStyle _tooltipStyle(FsTokens t) =>
    TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.bg);

class FsPoint {
  const FsPoint({
    required this.x,
    required this.y,
    required this.label,
    this.tooltip,
  });

  /// Where the point sits across the chart, in whole steps that rise from
  /// one point to the next: days since the first weigh-in, say. The chart
  /// spaces points by it, so a gap between readings shows as one.
  final double x;
  final double y;

  /// What the x-axis prints under this point — a date, or a set number.
  final String label;

  /// What touching the point reads out, e.g. "Sep 27 · 73.6 kg". Null falls
  /// back to the label and the bare value.
  final String? tooltip;
}

/// [text] as a screen reader should say it: "·" and "–" are read out as
/// symbols by some, so they become a comma and "to".
String _spoken(String text) =>
    text.replaceAll(' · ', ', ').replaceAll(' – ', ' to ');

/// How wide the widest of [labels] is in [style] at the user's text size.
double _widest(BuildContext context, Iterable<String> labels, TextStyle style) {
  final base = DefaultTextStyle.of(context).style.merge(style);
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: base),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return widest;
}

/// Which bar or point a chart's tooltip is showing for, kept between taps.
///
/// fl_chart's own handling shows a tooltip only while the finger is down, so
/// a quick tap flashed it and took it away before it could be read. Held here
/// instead, it stays up until the next tap: on another bar, which moves it;
/// on the chart's empty space, or anywhere off the chart, which puts it away.
/// A drag still moves it along as the finger goes.
///
/// Only a touch that turns out to be the chart's counts: a tap that lifts, a
/// long press, or a drag the chart won. A finger landing is not enough. The
/// Progress tab is a scrolling list of charts, so a scroll often starts on
/// one; kept from the moment it landed, its tooltip outlived the scroll.
mixin _KeepsTooltip<T extends StatefulWidget> on State<T> {
  int? _touched;

  /// [index] is the bar or point [event] landed on, or null for none.
  void _onTouch(FlTouchEvent event, int? index) {
    final chartsOwn =
        event is FlTapUpEvent ||
        event is FlLongPressStart ||
        event is FlLongPressMoveUpdate ||
        event is FlPanUpdateEvent;
    if (!chartsOwn) return;
    if (index != null) {
      if (index != _touched) setState(() => _touched = index);
    } else if (event is FlTapUpEvent) {
      _clear();
    }
  }

  void _clear() {
    if (_touched != null) setState(() => _touched = null);
  }

  /// Puts the tooltip away on a tap anywhere outside [chart].
  Widget _dismissedOutside(Widget chart) =>
      TapRegion(onTapOutside: (_) => _clear(), child: chart);
}

/// A series of readings over time, such as body weight.
///
/// Drawn as what it is: straight segments between real readings, a dot on
/// each one (the newest a little larger), and nothing shaded underneath. A
/// curve invented weights between weigh-ins, and a fill under body weight
/// read as an amount piling up, which it is not.
class FsLineChart extends StatefulWidget {
  const FsLineChart({
    super.key,
    required this.label,
    required this.points,
    required this.minYBand,
    this.referenceY,
    this.referenceLabel,
    this.color,
    this.height = 84,
  });

  /// What the chart measures, the start of what a screen reader hears.
  final String label;

  final List<FsPoint> points;

  /// The narrowest y window allowed, in the series' own unit.
  final double minYBand;

  /// A dashed horizontal line behind the series — a goal or starting weight.
  /// It is also what makes a one-point card read as a chart.
  final double? referenceY;

  /// What the dashed line is, written at its right-hand end ("Goal 70 kg").
  /// Without it nothing on the chart said what the dashed line meant.
  final String? referenceLabel;

  /// The series' own colour. Null is the accent, which is what a chart of
  /// training output uses. Body weight is not training output -- it is the
  /// body the training acts on -- and reads in blue so the two are not
  /// skimmed as the same measure.
  final Color? color;

  final double height;

  /// Whether the reference line's words go under it rather than over it:
  /// always on the side away from the newest point, which sits at the same
  /// right-hand end. Pinned above, they ran into the newest dot just as the
  /// user closed in on the goal.
  bool get _labelBelow =>
      points.isNotEmpty && referenceY != null && points.last.y >= referenceY!;

  /// The y window actually drawn: the data's range, widened to [minYBand]
  /// around its midpoint when the data is flatter than that, and always
  /// including [referenceY] so the dashed line cannot fall off the card --
  /// with room on its label's side for the label to sit inside the plot.
  (double, double) get resolvedYRange => _range(0.2);

  /// [resolvedYRange], leaving [labelShare] of the plot's height clear on the
  /// reference label's side of the line. The chart works the share out from
  /// the label's real height at the user's text size: a fixed fifth of the
  /// range left 12 px for a label 31 px tall at 2x, which then printed over
  /// the dates.
  (double, double) _range(double labelShare) {
    final values = [...points.map((p) => p.y), ?referenceY];
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

    if (referenceY != null && referenceLabel != null) {
      // Wanted: the gap between the line and the plot's edge is
      // [labelShare] of the whole window, once the window has grown to make
      // it. Solving gap / (rest + gap) = share for the gap gives this.
      final share = labelShare.clamp(0.0, 0.6);
      final ref = referenceY!;
      if (_labelBelow) {
        lo = math.min(lo, ref - share * (hi - ref) / (1 - share));
      } else {
        hi = math.max(hi, ref + share * (ref - lo) / (1 - share));
      }
    }
    return (lo, hi);
  }

  String _tooltipFor(int index) {
    final point = points[index];
    return point.tooltip ?? '${point.label} · ${point.y.toStringAsFixed(1)}';
  }

  @override
  State<FsLineChart> createState() => _FsLineChartState();

  /// The chart, with [touched]'s tooltip up when it is not null.
  Widget _build(
    BuildContext context, {
    required int? touched,
    required void Function(FlTouchEvent, int?) onTouch,
  }) {
    final t = context.fs;
    final series = color ?? t.accent;
    final newest = points.length - 1;
    final scaler = MediaQuery.textScalerOf(context);
    final referenceStyle = _axisStyle(t)
        .copyWith(fontSize: scaler.scale(11), fontWeight: FontWeight.w600);

    // The label's real height, its padding and a little air, as a share of
    // the plot (the chart less its row of dates).
    var labelShare = 0.0;
    if (referenceLabel != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: referenceLabel,
          style: DefaultTextStyle.of(context).style.merge(referenceStyle),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final plot = height - _axisSpace(context);
      labelShare = plot <= 0 ? 0.6 : (painter.height + 8) / plot;
      painter.dispose();
    }
    final (minY, maxY) = _range(labelShare);
    // One reading has no span to plot across; centre it rather than leave
    // it on the card's left edge.
    final lone = points.length == 1;

    final spoken = [
      for (var i = 0; i < points.length; i++) _spoken(_tooltipFor(i)),
    ].join('; ');

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: ['$label: $spoken', ?referenceLabel].join('. '),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minX = points.isEmpty ? 0.0 : points.first.x - (lone ? 1 : 0);
            final maxX = points.isEmpty ? 1.0 : points.last.x + (lone ? 1 : 0);
            // The readings named under the axis, by x: the newest always,
            // then, counting back, each far enough from the last one named
            // that no two dates touch -- the newest and oldest are pulled in
            // from the edges by half their width, hence the 1.5. Measured in
            // pixels rather than counted in readings, because readings sit by
            // their x: a week of daily weigh-ins crowds together, and a gap
            // of a month has room to spare. fl_chart's own interval also
            // labelled the last point beside the one it chose: "Sep 12Sep 19".
            final perX = constraints.maxWidth / math.max(maxX - minX, 1);
            // The tightest room between two neighbouring readings, which
            // decides the dots below. Not the average: spaced by date, a
            // week of daily weigh-ins after a long gap sits a pixel or two
            // apart while the average still looks roomy.
            var tightest = double.infinity;
            for (var i = 1; i < points.length; i++) {
              tightest = math.min(
                tightest,
                (points[i].x - points[i - 1].x) * perX,
              );
            }
            final room =
                _widest(context, points.map((p) => p.label), _axisStyle(t)) *
                    1.5 +
                8;
            final named = <int, int>{};
            double? lastNamed;
            for (var i = points.length - 1; i >= 0; i--) {
              final x = points[i].x;
              if (lastNamed == null || (lastNamed - x) * perX >= room) {
                named[x.round()] = i;
                lastNamed = x;
              }
            }

            final line = LineChartBarData(
              spots: [for (final p in points) FlSpot(p.x, p.y)],
              color: series,
              barWidth: 2,
              isStrokeCapRound: true,
              // The touched reading's guide line and ring, as fl_chart draws
              // them while a finger is down.
              showingIndicators: [?touched],
              // A dot per reading, each a real weigh-in; the newest
              // larger, and ringed in the card's colour so it stays
              // clear where it sits on the line.
              // A dot per reading while every two stand apart; past that
              // (a year of weekly weigh-ins is 7 px a reading) only the
              // newest, or the dots bead into a chain that hides the
              // line they sit on.
              dotData: FlDotData(
                checkToShowDot: (spot, bar) =>
                    tightest >= 14 || spot.x == points.last.x,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: index == newest ? 5 : 4,
                      color: series,
                      strokeWidth: 2,
                      strokeColor: t.surface,
                    ),
              ),
              belowBarData: BarAreaData(show: false),
            );

            return LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                minX: minX,
                maxX: maxX,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      // Every whole step is offered; only the readings picked
                      // above are named, each under its own dot.
                      interval: 1,
                      reservedSize: _axisSpace(context),
                      getTitlesWidget: (value, meta) {
                        final i = named[value.round()];
                        if (i == null) return const SizedBox.shrink();
                        // Kept inside the card: the first and last dates
                        // used to hang past its edges.
                        return SideTitleWidget(
                          meta: meta,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(
                            meta,
                            distanceFromEdge: 0,
                          ),
                          child: Text(points[i].label, style: _axisStyle(t)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: false,
                  touchCallback: (event, response) => onTouch(
                    event,
                    response?.lineBarSpots?.firstOrNull?.spotIndex,
                  ),
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => t.text,
                    tooltipBorderRadius: BorderRadius.circular(8),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          _tooltipFor(spot.spotIndex),
                          _tooltipStyle(t),
                        ),
                    ],
                  ),
                ),
                extraLinesData: referenceY == null
                    ? const ExtraLinesData()
                    : ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: referenceY!,
                            // text2, not the caption grey: in dark mode the
                            // line and its words all but vanished.
                            color: t.text2,
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                            label: HorizontalLineLabel(
                              show: referenceLabel != null,
                              alignment: _labelBelow
                                  ? Alignment.bottomRight
                                  : Alignment.topRight,
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              labelResolver: (_) => referenceLabel ?? '',
                              // Painted on the canvas, so scaled by hand to
                              // the user's text size; backed in the card's
                              // colour, so a segment of the line passing
                              // through it cannot strike it out.
                              style: referenceStyle.copyWith(
                                backgroundColor: t.surface,
                              ),
                            ),
                          ),
                        ],
                      ),
                lineBarsData: [line],
                showingTooltipIndicators: [
                  if (touched != null)
                    ShowingTooltipIndicators([
                      LineBarSpot(line, 0, line.spots[touched]),
                    ]),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FsLineChartState extends State<FsLineChart>
    with _KeepsTooltip<FsLineChart> {
  @override
  void didUpdateWidget(FsLineChart old) {
    super.didUpdateWidget(old);
    // Gone, or a different reading in its place: the tooltip would misreport.
    final touched = _touched;
    if (touched != null &&
        (touched >= widget.points.length ||
            widget._tooltipFor(touched) != old._tooltipFor(touched))) {
      _touched = null;
    }
  }

  @override
  Widget build(BuildContext context) => _dismissedOutside(
    widget._build(
      context,
      touched: _touched != null && _touched! < widget.points.length
          ? _touched
          : null,
      onTouch: _onTouch,
    ),
  );
}

/// One bar of an [FsBarChart].
class FsChartBar {
  const FsChartBar({
    required this.value,
    required this.label,
    required this.tooltip,
  });

  final double value;

  /// The word under the bar. Empty leaves this bar unlabelled.
  final String label;

  /// What touching the bar, or a screen reader, reads out, e.g.
  /// "Tue, Oct 13 · 2,400 kg".
  final String tooltip;
}

/// Amounts per day, week or month, such as training volume.
///
/// Bars rather than a line, because each is a total for its own stretch of
/// time and nothing lies between them: a smooth line over a week of training
/// and rest days drew it as a wave, inventing work on the rest days. Every bar
/// grows from zero, so the lightest week reads as light rather than as
/// nothing, which is what a window cut to the data's own range drew.
class FsBarChart extends StatefulWidget {
  const FsBarChart({
    super.key,
    required this.label,
    required this.bars,
    this.color,
    this.height = 120,
    this.showLabels = true,
    this.interactive = true,
  });

  /// What the chart measures, the start of what a screen reader hears.
  final String label;

  final List<FsChartBar> bars;

  /// Null is the accent: training output.
  final Color? color;

  final double height;

  /// False for a small preview whose card opens the full chart elsewhere.
  final bool showLabels;

  /// False where a tap belongs to the card around the chart.
  final bool interactive;

  @override
  State<FsBarChart> createState() => _FsBarChartState();

  /// The chart, with bar [touched]'s tooltip up when it is not null.
  Widget _build(
    BuildContext context, {
    required int? touched,
    required void Function(FlTouchEvent, int?) onTouch,
  }) {
    final t = context.fs;
    final top = bars.fold<double>(0, (most, bar) => math.max(most, bar.value));
    final maxY = top <= 0 ? 1.0 : top * 1.1; // all zeros keeps a valid scale

    // Every bar's words, in order: the chart's figures are painted on a
    // canvas a screen reader cannot see into.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label: ${bars.map((b) => _spoken(b.tooltip)).join('; ')}',
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / math.max(bars.length, 1);
            final rod = math.min(24.0, slot * 0.6);

            // One size for every label, the largest that lets the widest fit
            // its room. Each used to shrink alone to its own slot, so at
            // large text "Wed" came out smaller than "Thu" and the words ran
            // together. Room spans the empty slots between labelled bars,
            // which a year's every-other month name has.
            final labelled = bars.where((b) => b.label.isNotEmpty).length;
            final stride = labelled == 0
                ? 1
                : math.max(1, (bars.length / labelled).round());
            final room = math.max(0.0, slot * stride - 6);
            final natural = MediaQuery.textScalerOf(context).scale(11);
            final widest = _widest(
              context,
              bars.map((b) => b.label),
              _axisStyle(t),
            );
            final fontSize = widest > room && widest > 0
                ? natural * room / widest
                : natural;
            // Too narrow for any word at all: no labels rather than a
            // negative width.
            final labelsFit = room > 0 && fontSize >= 1;

            return BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                // The one line a bar chart needs: the zero the bars stand on,
                // which is also all a rest day shows.
                borderData: FlBorderData(
                  show: true,
                  border: Border(bottom: BorderSide(color: t.line2)),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: showLabels,
                      reservedSize: _axisSpace(context),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (!labelsFit ||
                            i < 0 ||
                            i >= bars.length ||
                            bars[i].label.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 4,
                          child: SizedBox(
                            width: room,
                            child: Text(
                              bars[i].label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              // Already sized for the user's text setting.
                              textScaler: TextScaler.noScaling,
                              style: _axisStyle(t).copyWith(fontSize: fontSize),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: interactive,
                  handleBuiltInTouches: false,
                  touchCallback: (event, response) =>
                      onTouch(event, response?.spot?.touchedBarGroupIndex),
                  // The whole column answers a touch, not just the bar: a
                  // light week's bar is the one people check, and it was a
                  // sliver to aim at.
                  allowTouchBarBackDraw: true,
                  touchExtraThreshold: EdgeInsets.symmetric(
                    horizontal: math.max(0, (slot - rod) / 2),
                  ),
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => t.text,
                    tooltipBorderRadius: BorderRadius.circular(8),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                          bars[groupIndex].tooltip,
                          _tooltipStyle(t),
                        ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < bars.length; i++)
                    BarChartGroupData(
                      x: i,
                      showingTooltipIndicators: [if (i == touched) 0],
                      barRods: [
                        BarChartRodData(
                          toY: bars[i].value,
                          // Thin, never filling its slot: the space between
                          // bars is what keeps them separate.
                          width: rod,
                          color: color ?? t.accent,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          // Invisible, but full height: what the touch above
                          // is measured against.
                          backDrawRodData: BackgroundBarChartRodData(toY: maxY),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FsBarChartState extends State<FsBarChart>
    with _KeepsTooltip<FsBarChart> {
  @override
  void didUpdateWidget(FsBarChart old) {
    super.didUpdateWidget(old);
    // Gone, or another stretch of time in its place: the tooltip would
    // misreport it.
    final touched = _touched;
    if (touched != null &&
        (touched >= widget.bars.length ||
            widget.bars[touched].tooltip != old.bars[touched].tooltip)) {
      _touched = null;
    }
  }

  @override
  Widget build(BuildContext context) => _dismissedOutside(
    widget._build(
      context,
      touched: _touched != null && _touched! < widget.bars.length
          ? _touched
          : null,
      onTouch: _onTouch,
    ),
  );
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

/// The prototype's progress ring, with a label in the hole.
///
/// Hand-painted rather than a package: this is one arc, and the file's whole
/// point is that fl_chart is the only charting dependency the app carries.
class FsRing extends StatelessWidget {
  const FsRing({
    super.key,
    required this.value,
    required this.color,
    required this.child,
    this.size = 132,
    this.stroke = 11,
  });

  /// 0..1. Clamped on the way to the painter -- this is drawn from a server
  /// figure, and a NaN sweep throws inside the canvas rather than drawing
  /// nothing.
  final double value;
  final Color color;
  final Widget child;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final safe = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: safe,
          color: color,
          track: t.line2,
          stroke: stroke,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, 6.283185307179586, false, base);

    if (value <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    // From twelve o'clock, clockwise.
    canvas.drawArc(
      rect,
      -1.5707963267948966,
      6.283185307179586 * value,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}

/// One column of [FsBars].
class FsBar {
  const FsBar({required this.label, required this.value});
  final String label;
  final double value;
}

/// The prototype's vertical bar column, scaled against the largest bar.
///
/// Distinct from FsBarRow, which is one horizontal bar with a label beside it
/// for the muscle breakdown. This is the shape the 7-day training load is
/// drawn in.
class FsBars extends StatelessWidget {
  const FsBars({
    super.key,
    required this.bars,
    required this.color,
    this.height = 78,
  });

  final List<FsBar> bars;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    // A rest week is legitimately all zeroes, so the largest bar can be zero
    // and the scale has to survive it rather than divide by it.
    final peak = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bar in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: peak <= 0
                            ? 0.02
                            : (bar.value / peak).clamp(0.02, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: bar.value <= 0 ? t.line2 : color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bar.label,
                      style: TextStyle(fontSize: 10, color: t.text3),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
