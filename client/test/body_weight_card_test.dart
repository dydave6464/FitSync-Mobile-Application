import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/presentation/widgets/body_weight_card.dart';

BodyWeightSeries series(
  List<(String, double)> raw, {
  BodyWeightReference? reference,
  bool widened = false,
  String unit = 'kg',
  BodyWeightPoint? start,
  int? entries,
}) => BodyWeightSeries(
  widened: widened,
  points: [for (final (d, w) in raw) BodyWeightPoint(loggedOn: d, weightKg: w)],
  reference: reference,
  unit: unit,
  start: start,
  entries: entries ?? raw.length,
);

/// Today, for the tests: 09:00 on 20 October 2026 in Manila, as a UTC
/// instant so the result is the same in any machine's time zone.
DateTime _oct20() => DateTime.utc(2026, 10, 20, 1);

Future<void> pumpCard(
  WidgetTester tester,
  BodyWeightSeries s, {
  String period = 'week',
  WeightUnit? unit,
  DateTime Function() now = _oct20,
}) => tester.pumpWidget(
  MaterialApp(
    theme: fsLightTheme(),
    home: Scaffold(
      body: BodyWeightCard(series: s, unit: unit, period: period, now: now),
    ),
  ),
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
              [('2026-09-10', 80), ('2026-09-18', 71.5)],
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
          body: BodyWeightCard(
            series: series([('2026-09-17', 71.8), ('2026-09-18', 71.5)]),
          ),
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

  // Day one: a lone dot on a "Start" line that sits on the dot says nothing.
  // The weight and what happens next say more (a goal line still shows).
  group('the first weigh-in', () {
    testWidgets('without a goal: the weight and a nudge, no chart', (
      tester,
    ) async {
      await pumpCard(
        tester,
        series([
          ('2026-10-20', 72.5),
        ], reference: const BodyWeightReference(kind: 'start', weightKg: 72.5)),
      );

      expect(find.text('72.5 kg'), findsOneWidget);
      expect(
        find.text('Weigh in again tomorrow to see your change.'),
        findsOneWidget,
      );
      expect(find.byType(FsLineChart), findsNothing);
    });

    testWidgets('with a goal: the goal line still shows, and the nudge', (
      tester,
    ) async {
      await pumpCard(
        tester,
        series([
          ('2026-10-20', 72.5),
        ], reference: const BodyWeightReference(kind: 'goal', weightKg: 68)),
      );

      expect(
        tester.widget<FsLineChart>(find.byType(FsLineChart)).referenceY,
        68,
      );
      expect(
        find.text('Weigh in again tomorrow to see your change.'),
        findsOneWidget,
      );
    });
  });

  group('the change since the last weigh-in', () {
    testWidgets('down since yesterday', (tester) async {
      await pumpCard(
        tester,
        series([('2026-10-19', 72.9), ('2026-10-20', 72.5)]),
      );

      expect(find.text('0.4 kg since yesterday'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Down 0.4 kg since yesterday')),
        findsOneWidget,
      );
      expect(
        find.text('Weigh in again tomorrow to see your change.'),
        findsNothing,
      );
    });

    testWidgets('up, after a gap, names the day', (tester) async {
      await pumpCard(
        tester,
        series([('2026-10-14', 72.0), ('2026-10-20', 72.3)]),
      );

      expect(find.text('0.3 kg since Oct 14'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('no change says so', (tester) async {
      await pumpCard(
        tester,
        series([('2026-10-19', 72.5), ('2026-10-20', 72.5)]),
      );

      expect(find.text('No change since yesterday'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
    });

    testWidgets('converts for an lb user', (tester) async {
      // 0.5 kg is 1.1023 lb, worked out by hand.
      await pumpCard(
        tester,
        series([('2026-10-19', 73.0), ('2026-10-20', 72.5)], unit: 'lb'),
        unit: WeightUnit.lb,
      );

      expect(find.text('1.1 lb since yesterday'), findsOneWidget);
    });

    testWidgets('neutral ink: whether down is good depends on the goal', (
      tester,
    ) async {
      await pumpCard(
        tester,
        series([('2026-10-19', 72.9), ('2026-10-20', 72.5)]),
      );

      final text = tester.widget<Text>(find.text('0.4 kg since yesterday'));
      final context = tester.element(find.text('0.4 kg since yesterday'));
      expect(text.style?.color, context.fs.text2);
    });
  });

  group('since you started', () {
    const start = BodyWeightPoint(loggedOn: '2026-09-01', weightKg: 74.0);

    testWidgets('from the fourth weigh-in', (tester) async {
      await pumpCard(
        tester,
        series(
          [('2026-10-18', 73.1), ('2026-10-19', 72.9), ('2026-10-20', 72.8)],
          start: start,
          entries: 4,
        ),
      );

      expect(find.text('1.2 kg since you started'), findsOneWidget);
    });

    testWidgets('not before', (tester) async {
      await pumpCard(
        tester,
        series(
          [('2026-10-19', 72.9), ('2026-10-20', 72.8)],
          start: start,
          entries: 3,
        ),
      );

      expect(find.textContaining('since you started'), findsNothing);
    });
  });

  testWidgets(
    'tapping the change explains daily ups and downs, and tapping again hides it',
    (tester) async {
      await pumpCard(
        tester,
        series([('2026-10-19', 72.9), ('2026-10-20', 72.5)]),
      );
      const note =
          'Day-to-day changes of up to about 1 kg are normal (water and food), so the trend over weeks says more than one day.';
      expect(find.text(note), findsNothing);

      await tester.tap(find.byKey(const Key('bodyWeight.change')));
      await tester.pumpAndSettle();
      expect(find.text(note), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('bodyWeight.change'))).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(find.byKey(const Key('bodyWeight.change')));
      await tester.pumpAndSettle();
      expect(find.text(note), findsNothing);
    },
  );

  group('the caption names what the chart shows', () {
    for (final (period, caption) in [
      ('week', 'Last 7 days'),
      ('month', 'Last 30 days'),
      ('year', 'Last 12 months'),
    ]) {
      testWidgets('$period: $caption', (tester) async {
        await pumpCard(
          tester,
          series([('2026-10-19', 72.9), ('2026-10-20', 72.5)]),
          period: period,
        );

        expect(find.text(caption), findsOneWidget);
        expect(find.text('Logged weekly'), findsNothing);
      });
    }
  });

  testWidgets(
    'change, since-start and the note fit a 320 dp phone at 2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: fsLightTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: BodyWeightCard(
                  series: series(
                    [('2026-10-14', 73.1), ('2026-10-20', 72.5)],
                    start: const BodyWeightPoint(
                      loggedOn: '2026-09-01',
                      weightKg: 74.0,
                    ),
                    entries: 6,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('bodyWeight.change')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  // "Since yesterday" is about today: the morning after two daily weigh-ins,
  // before weighing in, the change is from the 19th to the 20th, not to now.
  testWidgets('since yesterday only when the latest weigh-in is today', (
    tester,
  ) async {
    await pumpCard(
      tester,
      series([('2026-10-19', 72.9), ('2026-10-20', 72.5)]),
      // 07:00 on the 21st in Manila.
      now: () => DateTime.utc(2026, 10, 20, 23),
    );

    expect(find.text('0.4 kg since Oct 19'), findsOneWidget);
    expect(find.textContaining('yesterday'), findsNothing);
  });

  testWidgets('an older lone weigh-in asks for another, not for tomorrow', (
    tester,
  ) async {
    await pumpCard(
      tester,
      series(
        [('2026-10-02', 72.5)],
        reference: const BodyWeightReference(kind: 'start', weightKg: 72.5),
        widened: true,
      ),
    );

    expect(find.text('Weigh in again to see your change.'), findsOneWidget);
    expect(find.textContaining('tomorrow'), findsNothing);
  });

  testWidgets('with no chart there is no caption naming its period', (
    tester,
  ) async {
    await pumpCard(
      tester,
      series([
        ('2026-10-20', 72.5),
      ], reference: const BodyWeightReference(kind: 'start', weightKg: 72.5)),
    );

    expect(find.byType(FsLineChart), findsNothing);
    expect(find.text('Last 7 days'), findsNothing);
    expect(find.text('Add entry'), findsOneWidget);
  });

  // excludeSemantics drops the InkWell's own tap action, so the button node
  // has to carry one or a screen reader announces a button that does nothing.
  testWidgets('a screen reader can open the note from the change', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCard(
      tester,
      series([('2026-10-19', 72.9), ('2026-10-20', 72.5)]),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('Down 0.4 kg'))),
      matchesSemantics(
        isButton: true,
        hasTapAction: true,
        label: 'Down 0.4 kg since yesterday',
        hint: 'Shows what daily changes mean',
      ),
    );
    handle.dispose();
  });

  testWidgets('the note speaks pounds to an lb user', (tester) async {
    await pumpCard(
      tester,
      series([('2026-10-19', 73.0), ('2026-10-20', 72.5)], unit: 'lb'),
      unit: WeightUnit.lb,
    );
    await tester.tap(find.byKey(const Key('bodyWeight.change')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Day-to-day changes of up to about 2 lb are normal (water and food), so the trend over weeks says more than one day.',
      ),
      findsOneWidget,
    );
  });

  // Weigh-in dates are Manila days (the server's CURDATE on +08:00), so
  // "today" is too, whatever zone the phone is set to.
  testWidgets('today is the Manila day, like the weigh-in dates', (
    tester,
  ) async {
    await pumpCard(
      tester,
      series([('2026-10-19', 72.9), ('2026-10-20', 72.5)]),
      // 20:00 UTC on the 19th is 04:00 on the 20th in Manila.
      now: () => DateTime.utc(2026, 10, 19, 20),
    );

    expect(find.text('0.4 kg since yesterday'), findsOneWidget);
  });
}
