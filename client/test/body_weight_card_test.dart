import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/presentation/widgets/body_weight_card.dart';

BodyWeightSeries series(List<(String, double)> raw, {
  BodyWeightReference? reference,
  bool widened = false,
  String unit = 'kg',
}) => BodyWeightSeries(
      widened: widened,
      points: [for (final (d, w) in raw) BodyWeightPoint(loggedOn: d, weightKg: w)],
      reference: reference,
      unit: unit,
    );

void main() {
  testWidgets('one entry still draws a chart, not a lone dot', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: BodyWeightCard(series: series(
        [('2026-09-16', 71.4)],
        reference: const BodyWeightReference(kind: 'goal', weightKg: 68),
      )),
    )));

    expect(find.textContaining('71.4'), findsOneWidget);

    // The reference line itself is painted on fl_chart's canvas, not emitted
    // as a Text widget, so assert on what the card actually controls: that it
    // handed the chart a reference to draw.
    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.referenceY, 68);
    expect(chart.referenceLabel, 'goal');
    expect(chart.points.length, 1);
  });

  testWidgets('a widened series says so', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: BodyWeightCard(series: series(
        [('2026-08-01', 80), ('2026-08-08', 79)],
        widened: true,
      )),
    )));
    expect(find.textContaining('all entries'), findsOneWidget);
  });

  testWidgets('an lb user sees pounds, not the raw kilogram number', (tester) async {
    // Everything server-side is kilograms; `unit` is display metadata only.
    // A user whose weight_unit is lb must never see the bare kg figure on
    // the headline, the chart, the reference line, or the noise band.
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: BodyWeightCard(series: series(
        [('2026-09-16', 71.4)],
        reference: const BodyWeightReference(kind: 'goal', weightKg: 68),
        unit: 'lb',
      )),
    )));

    expect(find.textContaining('157.4'), findsOneWidget,
        reason: '71.4 kg is 157.4 lb');
    expect(find.textContaining('71.4'), findsNothing,
        reason: 'the raw kg number must not be shown to an lb user');

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.points.single.y, closeTo(157.41, 0.01),
        reason: 'the chart y-values must be converted too, not just the headline');
    expect(chart.referenceY, closeTo(149.91, 0.01),
        reason: 'the goal/start reference line is kg too');
    expect(chart.minYBand, closeTo(8.82, 0.01),
        reason: 'the noise band must convert with everything else, not stay a '
            'literal 4 -- which would mean something different in pounds');
  });

  testWidgets('no entries offers the action instead of blaming the user', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: BodyWeightCard(series: series(const [])),
    )));
    expect(find.text('Add entry'), findsOneWidget);
  });
}
