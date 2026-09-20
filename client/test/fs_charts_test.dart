import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';

void main() {
  testWidgets('a 200 g change does not fill the card', (tester) async {
    // Three near-identical weights. Without a floor the y-axis would zoom
    // until 200 grams looked like a cliff, which is the chart lying.
    final points = [
      FsPoint(x: 0, y: 71.4, label: 'Mon'),
      FsPoint(x: 1, y: 71.2, label: 'Tue'),
      FsPoint(x: 2, y: 71.3, label: 'Wed'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FsLineChart(points: points, minYBand: 4.0)),
      ),
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    final (minY, maxY) = chart.resolvedYRange;
    expect(maxY - minY, greaterThanOrEqualTo(4.0));
  });

  testWidgets('a wide range is not squashed to the band', (tester) async {
    final points = [
      FsPoint(x: 0, y: 60, label: 'a'),
      FsPoint(x: 1, y: 95, label: 'b'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FsLineChart(points: points, minYBand: 4.0)),
      ),
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    final (minY, maxY) = chart.resolvedYRange;
    expect(maxY - minY, greaterThan(35.0));
  });

  testWidgets('a single point still renders with its reference line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FsLineChart(
            points: [FsPoint(x: 0, y: 71.4, label: 'today')],
            referenceY: 68,
            referenceLabel: 'goal',
            minYBand: 4.0,
          ),
        ),
      ),
    );
    expect(find.byType(FsLineChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
