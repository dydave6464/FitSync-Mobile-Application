import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/presentation/widgets/body_weight_card.dart';

BodyWeightSeries series(List<(String, double)> raw, {
  BodyWeightReference? reference,
  bool widened = false,
}) => BodyWeightSeries(
      widened: widened,
      points: [for (final (d, w) in raw) BodyWeightPoint(loggedOn: d, weightKg: w)],
      reference: reference,
      unit: 'kg',
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

  testWidgets('no entries offers the action instead of blaming the user', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: BodyWeightCard(series: series(const [])),
    )));
    expect(find.text('Add entry'), findsOneWidget);
  });
}
