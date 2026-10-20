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
    this.period = 'week',
  });

  final BodyWeightSeries series;

  /// The Progress tab's period, `'week'`, `'month'` or `'year'`: what the
  /// chart covers, named in the caption under it.
  final String period;

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
    // A lone weigh-in IS the start, so a "Start" line would sit on its dot
    // and say nothing; one weigh-in draws a chart only for a goal line.
    final firstOnly = points.length == 1;
    final showChart = !firstOnly || reference?.kind == 'goal';
    final start = series.start;

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
            if (firstOnly)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Weigh in again tomorrow to see your change.',
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              )
            else
              _WeightChange(
                latest: points.last,
                previous: points[points.length - 2],
                // From the fourth weigh-in: before that, "since you
                // started" is just "since yesterday" said twice.
                start:
                    series.entries >= 4 &&
                        start != null &&
                        start.loggedOn != points.last.loggedOn
                    ? start
                    : null,
                unit: unit,
              ),
            const SizedBox(height: 8),
            if (showChart)
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
                // what the dashed line was. For a lone weigh-in it is drawn only as
                // a goal: a "Start" line would sit on the one dot.
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
                          : _periodCaption(period),
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

/// What the chart covers, named plainly. "Logged weekly" read like an
/// instruction to weigh in once a week, when every weigh-in is drawn.
String _periodCaption(String period) => switch (period) {
  'month' => 'Last 30 days',
  'year' => 'Last 12 months',
  _ => 'Last 7 days',
};

/// A weight change as the card states it: "0.4 kg", one decimal, in the
/// user's unit, or null when it rounds to nothing.
String? _amount(double deltaKg, WeightUnit unit) {
  final value = convertFromKg(deltaKg.abs(), unit);
  if (value < 0.05) return null;
  final fixed = value.toStringAsFixed(1);
  return '${fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed} ${unit.api}';
}

/// The change since the last weigh-in, and since the first once there are
/// enough, under the headline. Neutral ink with an arrow, never red or
/// green: whether down is good depends on the user's goal, and one day's
/// change is mostly water. Tapping it says so.
class _WeightChange extends StatefulWidget {
  const _WeightChange({
    required this.latest,
    required this.previous,
    required this.start,
    required this.unit,
  });

  final BodyWeightPoint latest;
  final BodyWeightPoint previous;
  final BodyWeightPoint? start;
  final WeightUnit unit;

  @override
  State<_WeightChange> createState() => _WeightChangeState();
}

class _WeightChangeState extends State<_WeightChange> {
  bool _explained = false;

  /// One line: an arrow and "0.4 kg since yesterday", or "No change …",
  /// with what a screen reader says for it.
  ({Widget row, String spoken}) _line(
    BuildContext context,
    double deltaKg,
    String since,
  ) {
    final t = context.fs;
    final amount = _amount(deltaKg, widget.unit);
    final text = amount == null ? 'No change $since' : '$amount $since';
    final spoken = amount == null
        ? text
        : '${deltaKg < 0 ? 'Down' : 'Up'} $text';
    return (
      spoken: spoken,
      row: Row(
        children: [
          if (amount != null) ...[
            Icon(
              deltaKg < 0 ? Icons.arrow_downward : Icons.arrow_upward,
              size: 15,
              color: t.text2,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 13, color: t.text2)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final days =
        BodyWeightCard._dayNumber(widget.latest.loggedOn) -
        BodyWeightCard._dayNumber(widget.previous.loggedOn);
    final since = days == 1
        ? 'since yesterday'
        : 'since ${shortDate(DateTime.parse(widget.previous.loggedOn))}';
    final lines = [
      _line(context, widget.latest.weightKg - widget.previous.weightKg, since),
      if (widget.start != null)
        _line(
          context,
          widget.latest.weightKg - widget.start!.weightKg,
          'since you started',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: lines.map((l) => l.spoken).join('. '),
          hint: _explained
              ? 'Hides what daily changes mean'
              : 'Shows what daily changes mean',
          excludeSemantics: true,
          child: InkWell(
            key: const Key('bodyWeight.change'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _explained = !_explained),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final l in lines) l.row],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.info_outline, size: 16, color: t.text3),
                ],
              ),
            ),
          ),
        ),
        if (_explained)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Day-to-day changes of up to about 1 kg are normal (water and food), so the trend over weeks says more than one day.',
              style: TextStyle(fontSize: 12, color: t.text2, height: 1.4),
            ),
          ),
      ],
    );
  }
}
