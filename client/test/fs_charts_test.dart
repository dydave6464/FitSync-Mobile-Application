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

    testWidgets('a screen reader hears every bar, in words it can say', (
      tester,
    ) async {
      // "·" and "–" are read aloud by some screen readers as symbols.
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Training volume: Mon, Oct 12, 0 kg; Tue, Oct 13, 2,400 kg;',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('large text keeps every bar label apart, all one size', (
      tester,
    ) async {
      // Each label used to shrink on its own to its slot: "MonTueWed", with
      // "Wed" smaller than "Thu".
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final rects = [for (final d in days) tester.getRect(find.text(d))];
      for (var i = 1; i < rects.length; i++) {
        expect(
          rects[i].left - rects[i - 1].right,
          greaterThanOrEqualTo(2),
          reason: '${days[i - 1]} and ${days[i]} run together',
        );
      }
      final sizes = {
        for (final d in days) tester.widget<Text>(find.text(d)).style!.fontSize,
      };
      expect(sizes, hasLength(1), reason: 'one size for every label');
    });

    testWidgets('a short bar can be touched anywhere in its column', (
      tester,
    ) async {
      // A light week is the one people check, and its bar was a sliver to
      // aim at.
      await _pump(
        tester,
        const FsBarChart(label: 'Training volume', bars: _week),
      );

      final data = _barData(tester);
      expect(data.barTouchData.allowTouchBarBackDraw, isTrue);
      for (final group in data.barGroups) {
        expect(group.barRods.single.backDrawRodData.toY, data.maxY);
        expect(group.barRods.single.backDrawRodData.show, isFalse);
      }
    });

    testWidgets('a chart squeezed narrower than its labels does not fail', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 30,
          child: FsBarChart(label: 'Training volume', bars: _week),
        ),
      );

      expect(tester.takeException(), isNull);
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

    group('a tapped bar keeps its tooltip', () {
      // fl_chart's own touch shows a tooltip only while the finger is down,
      // so a quick tap flashed it and took it away before it could be read.

      /// Where bar [i] of the week stands, in the middle of its column.
      Offset barAt(WidgetTester tester, int i) {
        final chart = tester.getRect(find.byType(BarChart));
        return Offset(
          chart.left + (i + 0.5) * chart.width / _week.length,
          chart.top + 30,
        );
      }

      List<int> showing(WidgetTester tester) => [
        for (final (i, group) in _barData(tester).barGroups.indexed)
          if (group.showingTooltipIndicators.isNotEmpty) i,
      ];

      testWidgets('after the finger lifts, until something else is tapped', (
        tester,
      ) async {
        await _pump(
          tester,
          const FsBarChart(label: 'Training volume', bars: _week),
        );
        expect(_barData(tester).barTouchData.handleBuiltInTouches, isFalse);

        await tester.tapAt(barAt(tester, 3));
        await tester.pump(const Duration(seconds: 5));
        expect(showing(tester), [3]);
        expect(_barData(tester).barGroups[3].showingTooltipIndicators, [0]);

        // Another bar moves it.
        await tester.tapAt(barAt(tester, 1));
        await tester.pump();
        expect(showing(tester), [1]);

        // A tap anywhere off the chart puts it away.
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        expect(showing(tester), isEmpty);
      });

      testWidgets('a preview that hands its taps to its card shows none', (
        tester,
      ) async {
        await _pump(
          tester,
          const FsBarChart(
            label: 'Training volume',
            bars: _week,
            interactive: false,
          ),
        );

        await tester.tapAt(barAt(tester, 3));
        await tester.pump();
        expect(showing(tester), isEmpty);
      });

      testWidgets('new numbers put an old tooltip away', (tester) async {
        // A tooltip left over a bar that now means another week would
        // misreport it.
        await _pump(
          tester,
          const FsBarChart(label: 'Training volume', bars: _week),
        );
        await tester.tapAt(barAt(tester, 3));
        await tester.pump();
        expect(showing(tester), [3]);

        await _pump(
          tester,
          FsBarChart(
            label: 'Training volume',
            bars: [
              for (final bar in _week)
                FsChartBar(
                  value: bar.value,
                  label: bar.label,
                  tooltip: 'Last week: ${bar.tooltip}',
                ),
            ],
          ),
        );
        expect(showing(tester), isEmpty);
      });
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
        label: 'Body weight',
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

    testWidgets('a tapped point keeps its tooltip until the next tap', (
      tester,
    ) async {
      // fl_chart's own touch shows it only while the finger is down.
      await pumpWeights(tester);
      expect(_lineData(tester).lineTouchData.handleBuiltInTouches, isFalse);

      List<int> showing() => [
        for (final tip in _lineData(tester).showingTooltipIndicators)
          for (final spot in tip.showingSpots) spot.spotIndex,
      ];

      // The middle weigh-in sits halfway across: x runs 0 to 2.
      final chart = tester.getRect(find.byType(LineChart));
      await tester.tapAt(Offset(chart.center.dx, chart.top + 20));
      await tester.pump(const Duration(seconds: 5));
      expect(showing(), [1]);
      expect(_lineData(tester).lineBarsData.single.showingIndicators, [1]);

      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(showing(), isEmpty);
    });

    testWidgets('the axis labels are readable, not the faint caption grey', (
      tester,
    ) async {
      await pumpWeights(tester);

      final style = tester.widget<Text>(find.text('Sep 27')).style!;
      expect(style.fontSize, greaterThanOrEqualTo(11));
      expect(style.color, FsTokens.light.text2);
    });

    testWidgets('dates never print on top of each other', (tester) async {
      // fl_chart always labelled the last point too, beside the one the
      // interval chose, so eight weekly entries printed "Sep 12Sep 19".
      final eight = [
        for (var i = 0; i < 8; i++)
          FsPoint(x: i.toDouble(), y: 70 + i / 10, label: 'Sep ${i + 1}0'),
      ];
      for (final (width, scale) in [(393.0, 1.0), (320.0, 2.0)]) {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _pump(
          tester,
          FsLineChart(label: 'Body weight', points: eight, minYBand: 4),
        );
        // fl_chart pulls the edge dates inside on the frame after.
        await tester.pump();

        final shown = [
          for (final p in eight)
            if (find.text(p.label).evaluate().isNotEmpty)
              tester.getRect(find.text(p.label)),
        ]..sort((a, b) => a.left.compareTo(b.left));
        expect(find.text('Sep 80'), findsOneWidget, reason: 'the newest');
        for (var i = 1; i < shown.length; i++) {
          expect(
            shown[i].left - shown[i - 1].right,
            greaterThanOrEqualTo(4),
            reason: 'at ${width.toInt()} dp, ${scale}x',
          );
        }
      }
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    });

    testWidgets('readings stand apart by their x, so gaps show', (
      tester,
    ) async {
      // Days since the first weigh-in: two weeks, then four with none.
      final gappy = [
        const FsPoint(x: 0, y: 72, label: 'Sep 1'),
        const FsPoint(x: 14, y: 71.6, label: 'Sep 15'),
        const FsPoint(x: 42, y: 70.8, label: 'Oct 13'),
      ];
      tester.view.physicalSize = const Size(393, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        FsLineChart(label: 'Body weight', points: gappy, minYBand: 4),
      );
      await tester.pump();

      final data = _lineData(tester);
      expect(data.lineBarsData.single.spots.map((s) => s.x), [0, 14, 42]);
      expect((data.minX, data.maxX), (0, 42));
      // Every date still printed under its own reading, none in the gap.
      for (final p in gappy) {
        expect(find.text(p.label), findsOneWidget, reason: p.label);
      }
      // And each under its own dot: two weeks in is a third of the way,
      // where by order it was half.
      final chart = tester.getRect(find.byType(LineChart));
      expect(
        tester.getCenter(find.text('Sep 15')).dx,
        closeTo(chart.left + chart.width * 14 / 42, 1),
      );
    });

    testWidgets('dates crowded together drop out, never the newest', (
      tester,
    ) async {
      // Two weigh-ins a day apart cannot both be named at this width.
      final crowded = [
        const FsPoint(x: 0, y: 72, label: 'Sep 1'),
        const FsPoint(x: 27, y: 71, label: 'Sep 28'),
        const FsPoint(x: 28, y: 70.8, label: 'Sep 29'),
      ];
      tester.view.physicalSize = const Size(393, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        FsLineChart(label: 'Body weight', points: crowded, minYBand: 4),
      );
      await tester.pump();

      expect(find.text('Sep 29'), findsOneWidget);
      expect(find.text('Sep 28'), findsNothing);
      expect(find.text('Sep 1'), findsOneWidget);
    });

    for (final (case_, newest, side) in [
      ('above', 70.4, Alignment.bottomRight),
      ('below', 69.6, Alignment.topRight),
    ]) {
      testWidgets('the goal label sits away from a newest point just $case_', (
        tester,
      ) async {
        // Pinned above the line, it ran into the newest dot just as the
        // user closed in on the goal: "Goal 70 k●".
        await _pump(
          tester,
          FsLineChart(
            label: 'Body weight',
            points: [
              const FsPoint(x: 0, y: 72, label: 'a'),
              FsPoint(x: 1, y: newest, label: 'b'),
            ],
            minYBand: 4,
            referenceY: 70,
            referenceLabel: 'Goal 70 kg',
          ),
        );

        final data = _lineData(tester);
        final line = data.extraLinesData.horizontalLines.single;
        expect(line.label.alignment, side);
        // And there is room for it on that side, inside the plot.
        final room = (data.maxY - data.minY) * 0.15;
        if (side == Alignment.bottomRight) {
          expect(data.minY, lessThanOrEqualTo(70 - room));
        } else {
          expect(data.maxY, greaterThanOrEqualTo(70 + room));
        }
      });
    }

    testWidgets('a long series keeps its line, dotting only the newest', (
      tester,
    ) async {
      // A year of weekly weigh-ins drew 52 ringed dots 7 px apart: a beaded
      // chain with no line left to see.
      final year = [
        for (var i = 0; i < 52; i++)
          FsPoint(x: i.toDouble(), y: 75 - i / 20, label: 'w$i'),
      ];
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        FsLineChart(label: 'Body weight', points: year, minYBand: 4),
      );

      final bar = _lineData(tester).lineBarsData.single;
      expect(bar.dotData.checkToShowDot(bar.spots.first, bar), isFalse);
      expect(bar.dotData.checkToShowDot(bar.spots[25], bar), isFalse);
      expect(bar.dotData.checkToShowDot(bar.spots.last, bar), isTrue);
    });

    testWidgets(
      'at large text the goal label below the line clears the dates',
      (tester) async {
        // A fixed fifth of the range left 12 px for a label 31 px tall at 2x,
        // so "Goal 70 kg" printed over the dates.
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          const FsLineChart(
            label: 'Body weight',
            points: [
              FsPoint(x: 0, y: 74, label: 'a'),
              FsPoint(x: 1, y: 73, label: 'b'),
            ],
            minYBand: 4,
            referenceY: 70,
            referenceLabel: 'Goal 70 kg',
            height: 104,
          ),
        );

        final data = _lineData(tester);
        // The plot is the chart's height less the date row (11 px text at 2x,
        // 1.4 line height, plus 6), and the label 22 px text at 2x plus its
        // 3 px padding each side: at least 28 px below the line.
        const plot = 104 - (22 * 1.4 + 6);
        final below = (70 - data.minY) / (data.maxY - data.minY) * plot;
        expect(below, greaterThanOrEqualTo(28));
      },
    );

    testWidgets('the goal label grows with the text size', (tester) async {
      // Painted on the canvas, it stayed 11 px at any setting.
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpWeights(tester);

      final line = _lineData(tester).extraLinesData.horizontalLines.single;
      expect(line.label.style!.fontSize, 22);
    });

    testWidgets('a screen reader hears every reading and the goal', (
      tester,
    ) async {
      // The goal used to live only on the canvas, where nothing reads it.
      final handle = tester.ensureSemantics();
      await pumpWeights(tester);

      expect(
        find.bySemanticsLabel(
          'Body weight: Sep 20, 74.2 kg; Sep 27, 73.6 kg; Oct 4, 72.5 kg. '
          'Goal 70 kg',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a lone weigh-in sits in the middle, not on the edge', (
      tester,
    ) async {
      await _pump(
        tester,
        const FsLineChart(
          label: 'Body weight',
          points: [FsPoint(x: 0, y: 71.4, label: 'Sep 16')],
          minYBand: 4,
        ),
      );

      final data = _lineData(tester);
      expect(data.minX, lessThan(0));
      expect(data.maxX, greaterThan(0));
      expect(data.maxX, -data.minX);
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
        home: Scaffold(
          body: FsLineChart(label: 'Weight', points: points, minYBand: 4.0),
        ),
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
        home: Scaffold(
          body: FsLineChart(label: 'Weight', points: points, minYBand: 4.0),
        ),
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
            label: 'Weight',
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
