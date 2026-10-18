import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';

Future<void> _pump(WidgetTester tester, Widget chart) => tester.pumpWidget(
  MaterialApp(
    theme: fsLightTheme(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(20), child: chart),
    ),
  ),
);

/// A training week as the volume card hands it over: three sessions and four
/// rest days.
const _week = [
  FsChartBar(value: 0, label: 'Mon', tooltip: 'Mon, Oct 12 · 0 kg'),
  FsChartBar(value: 2400, label: 'Tue', tooltip: 'Tue, Oct 13 · 2,400 kg'),
  FsChartBar(value: 0, label: 'Wed', tooltip: 'Wed, Oct 14 · 0 kg'),
  FsChartBar(value: 3100, label: 'Thu', tooltip: 'Thu, Oct 15 · 3,100 kg'),
  FsChartBar(value: 0, label: 'Fri', tooltip: 'Fri, Oct 16 · 0 kg'),
  FsChartBar(value: 2800, label: 'Sat', tooltip: 'Sat, Oct 17 · 2,800 kg'),
  FsChartBar(value: 0, label: 'Sun', tooltip: 'Today · 0 kg'),
];

BarChartData _barData(WidgetTester tester) =>
    tester.widget<BarChart>(find.byType(BarChart)).data;

LineChartData _lineData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

void main() {
  group('FsBarChart', () {
    testWidgets('bars grow from zero, not from the smallest week', (
      tester,
    ) async {
      // From the lightest week up, 5,200 kg drew as nothing beside 7,000.
      await _pump(
        tester,
        const FsBarChart(
          label: 'Training volume',
          bars: [
            FsChartBar(value: 5200, label: 'a', tooltip: 'a'),
            FsChartBar(value: 6100, label: 'b', tooltip: 'b'),
            FsChartBar(value: 7000, label: 'c', tooltip: 'c'),
          ],
        ),
      );

      expect(_barData(tester).minY, 0);
      expect(_barData(tester).maxY, greaterThanOrEqualTo(7000));
    });

    testWidgets('a rest day is an empty slot, not a dip between days', (
      tester,
    ) async {
      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      final heights = [
        for (final group in _barData(tester).barGroups)
          group.barRods.single.toY,
      ];
      expect(heights, [0, 2400, 0, 3100, 0, 2800, 0]);
    });

    testWidgets('every bar with a label shows it', (tester) async {
      // A week thinned to every other day hid the days trained.
      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(day), findsOneWidget, reason: day);
      }
    });

    testWidgets('the axis labels are readable, not the faint caption grey', (
      tester,
    ) async {
      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      final style = tester.widget<Text>(find.text('Tue')).style!;
      expect(style.fontSize, greaterThanOrEqualTo(11));
      expect(style.color, FsTokens.light.text2);
    });

    testWidgets('touching a bar reads its own words, not a raw number', (
      tester,
    ) async {
      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      final data = _barData(tester);
      final group = data.barGroups[3];
      final item = data.barTouchData.touchTooltipData.getTooltipItem(
        group,
        3,
        group.barRods.single,
        0,
      );
      expect(item!.text, 'Thu, Oct 15 · 3,100 kg');
    });

    testWidgets('a screen reader hears every bar', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      expect(
        find.bySemanticsLabel(
          RegExp(r'^Training volume: Mon, Oct 12 · 0 kg; Tue, Oct 13'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('fits a 320 dp phone at 2.0x text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('FsLineChart', () {
    final weighIns = [
      const FsPoint(
        x: 0,
        y: 74.2,
        label: 'Sep 20',
        tooltip: 'Sep 20 · 74.2 kg',
      ),
      const FsPoint(
        x: 1,
        y: 73.6,
        label: 'Sep 27',
        tooltip: 'Sep 27 · 73.6 kg',
      ),
      const FsPoint(x: 2, y: 72.5, label: 'Oct 4', tooltip: 'Oct 4 · 72.5 kg'),
    ];

    Future<void> pumpWeights(WidgetTester tester) => _pump(
      tester,
      FsLineChart(
        points: weighIns,
        minYBand: 4,
        referenceY: 70,
        referenceLabel: 'Goal 70 kg',
      ),
    );

    testWidgets('every weigh-in is a dot on the line', (tester) async {
      await pumpWeights(tester);

      final bar = _lineData(tester).lineBarsData.single;
      expect(bar.dotData.show, isTrue);
      for (final spot in bar.spots) {
        expect(bar.dotData.checkToShowDot(spot, bar), isTrue);
      }
    });

    testWidgets('the line is drawn straight, with nothing shaded under it', (
      tester,
    ) async {
      // A curve invents weights between weigh-ins, and a fill under body
      // weight reads as an amount, which it is not.
      await pumpWeights(tester);

      final bar = _lineData(tester).lineBarsData.single;
      expect(bar.isCurved, isFalse);
      expect(bar.belowBarData.show, isFalse);
    });

    testWidgets('the dashed reference line names itself where it is drawn', (
      tester,
    ) async {
      // Unlabelled, the dashed line was a puzzle: nothing said it was the goal.
      await pumpWeights(tester);

      final line = _lineData(tester).extraLinesData.horizontalLines.single;
      expect(line.y, 70);
      expect(line.label.show, isTrue);
      expect(line.label.labelResolver(line), 'Goal 70 kg');
    });

    testWidgets('touching a point reads its own words', (tester) async {
      await pumpWeights(tester);

      final data = _lineData(tester);
      final bar = data.lineBarsData.single;
      final items = data.lineTouchData.touchTooltipData.getTooltipItems([
        LineBarSpot(bar, 0, bar.spots[1]),
      ]);
      expect(items.single!.text, 'Sep 27 · 73.6 kg');
    });

    testWidgets('the axis labels are readable, not the faint caption grey', (
      tester,
    ) async {
      await pumpWeights(tester);

      final style = tester.widget<Text>(find.text('Sep 27')).style!;
      expect(style.fontSize, greaterThanOrEqualTo(11));
      expect(style.color, FsTokens.light.text2);
    });
  });

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
