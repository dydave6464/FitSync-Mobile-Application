import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/revenue_chart.dart';

import 'helpers/fake_admin_repository.dart';

Future<void> _pump(
  WidgetTester tester,
  List<RevenueBar> months, {
  bool dark = false,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? fsDarkTheme() : fsLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 640),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: RevenueChart(months: months),
          ),
        ),
      ),
    ),
  );
}

BarChartData _data(WidgetTester tester) =>
    tester.widget<BarChart>(find.byType(BarChart)).data;

void main() {
  testWidgets('each month stacks Pro under Ads in the two series colours', (
    tester,
  ) async {
    await _pump(tester, sampleRevenueBars);
    final t = FsTokens.light;

    final groups = _data(tester).barGroups;
    expect(groups, hasLength(6));
    final nov = groups.last.barRods.single;
    expect(nov.toY, 3486);
    final items = nov.rodStackItems;
    expect(items, hasLength(2));
    expect(items[0].color, t.accentFill);
    expect(items[0].fromY, 0);
    // A sliver of the card shows between the two segments.
    expect(items[0].toY, closeTo(2286, 3486 * 0.05));
    expect(items[0].toY, lessThan(2286));
    expect(items[1].color, t.blue);
    expect(items[1].fromY, 2286);
    expect(items[1].toY, 3486);
  });

  testWidgets('a legend names both series in words', (tester) async {
    await _pump(tester, sampleRevenueBars);

    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Ads'), findsOneWidget);
  });

  testWidgets("each bar's total is printed above it", (tester) async {
    await _pump(tester, sampleRevenueBars);

    expect(find.text('₱3,486'), findsOneWidget);
    expect(find.text('₱2,739'), findsOneWidget);
    expect(find.text('₱0'), findsNWidgets(4));
    final total = tester.getRect(find.text('₱3,486'));
    final initial = tester.getRect(find.text('N'));
    expect(total.bottom, lessThan(initial.top));
    // Over its own bar.
    expect((total.center.dx - initial.center.dx).abs(), lessThan(1));
  });

  testWidgets('month initials run along the axis', (tester) async {
    await _pump(tester, sampleRevenueBars);

    for (final initial in ['J', 'A', 'S', 'O', 'N']) {
      expect(find.text(initial), findsWidgets);
    }
    expect(find.text('J'), findsNWidgets(2));
  });

  testWidgets('a screen reader hears every month and its total', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, sampleRevenueBars);

    expect(
      find.bySemanticsLabel(
        'Revenue, last 6 months: Jun ₱0, Jul ₱0, Aug ₱0, Sep ₱0, '
        'Oct ₱2,739, Nov ₱3,486',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a year of nothing draws without error', (tester) async {
    await _pump(tester, [
      for (final m in ['01', '02', '03', '04', '05', '06'])
        RevenueBar(month: '2026-$m', proPhp: 0, adsPhp: 0),
    ]);

    expect(tester.takeException(), isNull);
    expect(_data(tester).maxY, greaterThan(0));
    expect(find.text('₱0'), findsNWidgets(6));
  });

  testWidgets('dark theme uses the dark series colours', (tester) async {
    await _pump(tester, sampleRevenueBars, dark: true);
    final t = FsTokens.dark;

    final items = _data(tester).barGroups.last.barRods.single.rodStackItems;
    expect(items[0].color, t.accentFill);
    expect(items[1].color, t.blue);
  });

  testWidgets('large totals at twice the text size do not overflow', (
    tester,
  ) async {
    await _pump(tester, [
      for (final m in ['06', '07', '08', '09', '10', '11'])
        RevenueBar(month: '2026-$m', proPhp: 123456.5, adsPhp: 98765),
    ], textScale: 2);

    expect(tester.takeException(), isNull);
  });
}
