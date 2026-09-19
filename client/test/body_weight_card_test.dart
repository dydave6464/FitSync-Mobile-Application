import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/core/theme.dart';
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
    expect(chart.points.length, 1);
  });

  // The chart draws no y-axis, so the dashed line's value can only be read
  // off a label -- and the prototype puts that in the card header, opposite
  // the headline, rather than inside the plot. Labelling the line itself
  // leaves the number floating over the data it is not part of.
  testWidgets('the goal reads in the card header, not on the chart',
      (tester) async {
    await tester.pumpWidget(MaterialApp(theme: fsLightTheme(), home: Scaffold(
      body: BodyWeightCard(series: series(
        [('2026-09-18', 71.5)],
        reference: const BodyWeightReference(kind: 'goal', weightKg: 75),
      )),
    )));

    expect(find.text('goal 75 kg'), findsOneWidget);
    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.referenceLabel, isNull, reason: 'the header carries it now');
    expect(chart.referenceY, 75, reason: 'the line itself stays');
  });

  testWidgets('a starting-weight reference reads the same way', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: fsLightTheme(), home: Scaffold(
      body: BodyWeightCard(series: series(
        [('2026-09-18', 71.5)],
        reference: const BodyWeightReference(kind: 'start', weightKg: 80),
      )),
    )));

    expect(find.text('start 80 kg'), findsOneWidget);
  });

  // 68 kg is 149.914... lb, derived by hand rather than through the same
  // conversion the card uses.
  testWidgets('the header goal converts for an lb user', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: fsLightTheme(), home: Scaffold(
      body: BodyWeightCard(series: series(
        [('2026-09-16', 71.4)],
        reference: const BodyWeightReference(kind: 'goal', weightKg: 68),
        unit: 'lb',
      )),
    )));

    expect(find.text('goal 149.9 lb'), findsOneWidget);
  });

  // Body weight is the one chart here that is not about training output, and
  // the prototype colours it apart from the accent for exactly that reason.
  testWidgets('the body-weight chart reads in blue, not the accent',
      (tester) async {
    await tester.pumpWidget(MaterialApp(theme: fsLightTheme(), home: Scaffold(
      body: BodyWeightCard(series: series([('2026-09-18', 71.5)])),
    )));

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.color, FsTokens.light.blue);
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
