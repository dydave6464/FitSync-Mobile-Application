import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/presentation/widgets/body_weight_card.dart';

BodyWeightSeries series(
  List<(String, double)> raw, {
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodyWeightCard(
            series: series(
              [('2026-09-16', 71.4)],
              reference: const BodyWeightReference(kind: 'goal', weightKg: 68),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('71.4'), findsOneWidget);

    // The reference line itself is painted on fl_chart's canvas, not emitted
    // as a Text widget, so assert on what the card actually controls: that it
    // handed the chart a reference to draw.
    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.referenceY, 68);
    expect(chart.points.length, 1);
  });

  // The dashed line used to be named only in the header, opposite the
  // headline; on the phone nothing said what the dashed line was. It names
  // itself where it is drawn now, and the header no longer repeats it.
  testWidgets('the goal line is labelled on the chart, not in the header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: BodyWeightCard(
            series: series(
              [('2026-09-18', 71.5)],
              reference: const BodyWeightReference(kind: 'goal', weightKg: 75),
            ),
          ),
        ),
      ),
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.referenceY, 75);
    expect(chart.referenceLabel, 'Goal 75 kg');
    expect(find.text('goal 75 kg'), findsNothing);
  });

  testWidgets('a starting-weight line is labelled the same way', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: BodyWeightCard(
            series: series(
              [('2026-09-18', 71.5)],
              reference: const BodyWeightReference(kind: 'start', weightKg: 80),
            ),
          ),
        ),
      ),
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.referenceLabel, 'Start 80 kg');
  });

  // 68 kg is 149.914... lb, derived by hand rather than through the same
  // conversion the card uses.
  testWidgets('the goal line\'s label converts for an lb user', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: BodyWeightCard(
            series: series(
              [('2026-09-16', 71.4)],
              reference: const BodyWeightReference(kind: 'goal', weightKg: 68),
              unit: 'lb',
            ),
          ),
        ),
      ),
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.referenceLabel, 'Goal 149.9 lb');
  });

  testWidgets('dates read as words, and each point says what it was', (
    tester,
  ) async {
    // "09-16" was the raw ISO date with its year cut off.
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: BodyWeightCard(
            series: series([('2026-09-16', 71.4), ('2026-09-23', 70.9)]),
          ),
        ),
      ),
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.points.map((p) => p.label), ['Sep 16', 'Sep 23']);
    expect(chart.points.last.tooltip, 'Sep 23 · 70.9 kg');
  });

  testWidgets('weigh-ins sit apart by the days between them', (tester) async {
    // Spaced by order, a three-week gap looked like any other week, so a
    // missed stretch of weigh-ins was hidden.
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: BodyWeightCard(
            series: series([
              ('2026-09-01', 72.0),
              ('2026-09-08', 71.6),
              ('2026-09-29', 70.8),
              // Across the change of month and of clocks in many places.
              ('2026-11-02', 70.1),
            ]),
          ),
        ),
      ),
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.points.map((p) => p.x), [0, 7, 28, 62]);
  });

  // Body weight is the one chart here that is not about training output, and
  // the prototype colours it apart from the accent for exactly that reason.
  testWidgets('the body-weight chart reads in blue, not the accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: BodyWeightCard(series: series([('2026-09-18', 71.5)])),
        ),
      ),
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.color, FsTokens.light.blue);
  });

  testWidgets('fits a 320 dp phone at 2.0x text, footer included', (
    tester,
  ) async {
    // The footer's caption and Add entry chip shared one unbending row and
    // overflowed it by 57 px.
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyWeightCard(
              series: series(
                [('2026-09-16', 71.4), ('2026-09-23', 70.9)],
                reference: const BodyWeightReference(
                  kind: 'goal',
                  weightKg: 68,
                ),
                widened: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  // Add entry is drawn about 30 dp tall at the foot of the card; the card's
  // padding under it is where the rest of a 48 dp target goes.
  for (final (name, raw) in [
    ('with no entries yet', <(String, double)>[]),
    ('under the chart', [('2026-09-16', 71.4)]),
  ]) {
    testWidgets('Add entry answers a tap 7 dp off its pill, $name', (
      tester,
    ) async {
      var adds = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: fsLightTheme(),
          home: Scaffold(
            body: ListView(
              children: [
                BodyWeightCard(series: series(raw), onAdd: () => adds++),
              ],
            ),
          ),
        ),
      );

      final pill = tester.getRect(find.byType(FsChip));
      await tester.tapAt(pill.topCenter - const Offset(0, 7));
      await tester.tapAt(pill.bottomCenter + const Offset(0, 7));
      expect(adds, 2);
    });
  }

  testWidgets('a widened series says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodyWeightCard(
            series: series([
              ('2026-08-01', 80),
              ('2026-08-08', 79),
            ], widened: true),
          ),
        ),
      ),
    );
    expect(find.textContaining('all entries'), findsOneWidget);
  });

  testWidgets('an lb user sees pounds, not the raw kilogram number', (
    tester,
  ) async {
    // Everything server-side is kilograms; `unit` is display metadata only.
    // A user whose weight_unit is lb must never see the bare kg figure on
    // the headline, the chart, the reference line, or the noise band.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodyWeightCard(
            series: series(
              [('2026-09-16', 71.4)],
              reference: const BodyWeightReference(kind: 'goal', weightKg: 68),
              unit: 'lb',
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('157.4'),
      findsOneWidget,
      reason: '71.4 kg is 157.4 lb',
    );
    expect(
      find.textContaining('71.4'),
      findsNothing,
      reason: 'the raw kg number must not be shown to an lb user',
    );

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(
      chart.points.single.y,
      closeTo(157.41, 0.01),
      reason: 'the chart y-values must be converted too, not just the headline',
    );
    expect(
      chart.referenceY,
      closeTo(149.91, 0.01),
      reason: 'the goal/start reference line is kg too',
    );
    expect(
      chart.minYBand,
      closeTo(8.82, 0.01),
      reason:
          'the noise band must convert with everything else, not stay a '
          'literal 4 -- which would mean something different in pounds',
    );
  });

  testWidgets('no entries offers the action instead of blaming the user', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BodyWeightCard(series: series(const []))),
      ),
    );
    expect(find.text('Add entry'), findsOneWidget);
  });
}
